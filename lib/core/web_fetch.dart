import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../tools/webview_loader.dart';
import 'net_error.dart';

/// 一次网页/接口抓取的结果
class WebContent {
  const WebContent({
    required this.url,
    this.title = '',
    this.text = '',
    this.kind = 'html',
    this.error,
  });

  final String url;
  final String title;
  final String text;

  /// html | json | text
  final String kind;
  final String? error;

  bool get ok => error == null && text.trim().isNotEmpty;
}

/// 智能抓取网页内容。
///
/// 分两层，顺序很重要：
///  1. **直连 HTTP**：对 JSON 接口（如 Mapbox 的 API）最快也最可靠，
///     走 WebView 反而可能因为渲染而拿不到原始 JSON。
///  2. **无头 WebView**：HTML 页面里正文太短（说明是 JS 渲染的 SPA）时兜底，
///     这时候只有真浏览器才能拿到内容。
class WebFetcher {
  const WebFetcher._();

  static Future<WebContent> fetch(
    String rawUrl, {
    int maxChars = 16000,
    Duration httpTimeout = const Duration(seconds: 15),
  }) async {
    final String url = rawUrl.trim();
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      return WebContent(url: url, error: '网址不合法');
    }

    // ---------- 第一层：直连 ----------
    final WebContent? direct = await _tryDirectHttp(uri, maxChars, httpTimeout);
    if (direct != null && direct.ok) return direct;

    // ---------- 第二层：真实浏览器 ----------
    final WebContent? browser = await _tryWebView(uri, maxChars);
    if (browser != null && browser.ok) return browser;

    // 两层都失败时，把已知信息尽量带出去
    final String reason = direct?.error ?? browser?.error ?? '抓取失败';
    return WebContent(url: url, error: reason);
  }

  static Future<WebContent?> _tryDirectHttp(
    Uri uri,
    int maxChars,
    Duration timeout,
  ) async {
    try {
      // 瞬时中断（ECONNABORTED / ECONNRESET / 超时）重试两三次通常就过了。
      // 域名解析失败、证书错误这类重试无用，NetError 内部会区分。
      final http.Response resp = await NetError.retry(
        () => http.get(
          uri,
          headers: <String, String>{
            'User-Agent': WebViewLoader.mobileUserAgent,
            'Accept': '*/*',
          },
        ).timeout(timeout),
        // 只重试一次：网页插入是交互操作，不能让用户等太久
        attempts: 2,
      );

      final String ct =
          (resp.headers['content-type'] ?? '').toLowerCase();

      // 用 bodyBytes 自己解码：有些接口不带 charset，交给 response.body
      // 会按 latin1 解，中文直接乱码。
      final String body = utf8.decode(resp.bodyBytes, allowMalformed: true);

      if (resp.statusCode != 200) {
        // 4xx/5xx 也可能是 JSON 错误体，带出去更有用
        if (ct.contains('json')) {
          return WebContent(
            url: uri.toString(),
            kind: 'json',
            text: _prettyJson(body, maxChars),
            error: 'HTTP ${resp.statusCode}',
          );
        }
        return WebContent(
          url: uri.toString(),
          error: 'HTTP ${resp.statusCode}',
        );
      }

      if (ct.contains('json') || _looksLikeJson(body)) {
        return WebContent(
          url: uri.toString(),
          kind: 'json',
          text: _prettyJson(body, maxChars),
        );
      }

      if (ct.contains('text/plain') ||
          ct.contains('text/csv') ||
          ct.contains('text/markdown')) {
        return WebContent(
          url: uri.toString(),
          kind: 'text',
          text: _clip(body.trim(), maxChars),
        );
      }

      // HTML：先做一次轻量去标签。正文够长就直接用，省掉一次 WebView 加载
      if (ct.contains('html') || body.contains('<html') || body.contains('<!DOCTYPE')) {
        final String text = stripHtml(body);
        if (text.length >= 400) {
          return WebContent(
            url: uri.toString(),
            kind: 'html',
            title: _extractTitle(body) ?? '',
            text: _clip(text, maxChars),
          );
        }
        // 太短 → 多半是 JS 渲染的空壳，交给 WebView
        return WebContent(
          url: uri.toString(),
          error: '页面正文过短（${text.length} 字符），需要浏览器渲染',
        );
      }

      return WebContent(
        url: uri.toString(),
        kind: 'text',
        text: _clip(body.trim(), maxChars),
      );
    } on TimeoutException {
      return WebContent(url: uri.toString(), error: 'HTTP 请求超时（已重试）');
    } catch (e) {
      return WebContent(url: uri.toString(), error: NetError.describe(e));
    }
  }

  static Future<WebContent?> _tryWebView(Uri uri, int maxChars) async {
    try {
      final String? raw = await WebViewLoader.load(
        url: uri.toString(),
        js: WebViewLoader.extractPageJs,
        isDone: (String s) {
          try {
            final Map<String, dynamic> m = Map<String, dynamic>.from(
                jsonDecode(WebViewLoader.unwrapJsString(s)) as Map);
            return ((m['text'] ?? '') as String).length >= 400;
          } catch (_) {
            return false;
          }
        },
      );

      if (raw == null) {
        return WebContent(url: uri.toString(), error: '浏览器加载失败或超时');
      }

      final Map<String, dynamic> m = Map<String, dynamic>.from(
          jsonDecode(WebViewLoader.unwrapJsString(raw)) as Map);

      final String text = (m['text'] ?? '').toString().trim();
      if (text.isEmpty) {
        return WebContent(url: uri.toString(), error: '页面没有可读文本');
      }

      return WebContent(
        url: (m['url'] ?? uri.toString()).toString(),
        title: (m['title'] ?? '').toString(),
        kind: 'html',
        text: _clip(text, maxChars),
      );
    } catch (e) {
      return WebContent(url: uri.toString(), error: '浏览器抓取异常：$e');
    }
  }

  // ---------------------------------------------------------------- 工具

  static bool _looksLikeJson(String s) {
    final String t = s.trimLeft();
    return t.startsWith('{') || t.startsWith('[');
  }

  /// JSON 尽量美化；解析不了就原样截断（有些接口返回的不是严格 JSON）
  static String _prettyJson(String body, int maxChars) {
    try {
      final dynamic j = jsonDecode(body);
      return _clip(
        const JsonEncoder.withIndent('  ').convert(j),
        maxChars,
      );
    } catch (_) {
      return _clip(body.trim(), maxChars);
    }
  }

  static String _clip(String s, int maxChars) {
    if (s.length <= maxChars) return s;
    return '${s.substring(0, maxChars)}\n…（内容过长已截断，共 ${s.length} 字符）';
  }

  static String? _extractTitle(String html) {
    final RegExpMatch? m =
        RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false)
            .firstMatch(html);
    if (m == null) return null;
    return stripHtml(m.group(1) ?? '');
  }

  /// 去标签 + 去脚本样式，得到可读文本
  static String stripHtml(String html) {
    String s = html;
    s = s.replaceAll(
        RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ');
    s = s.replaceAll(
        RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#x27;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&hellip;', '…');
    s = s.replaceAll(RegExp(r'[ \t\u00A0]+'), ' ');
    s = s.replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n');
    return s.trim();
  }
}
