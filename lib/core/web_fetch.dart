import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
      //
      // **必须先拿到响应头再决定要不要读正文。**
      //
      // 原来直接 `http.get(...)`：它会把**整个响应体**读进内存。
      // 抓到一个视频链接时，就真的把整个视频下载完（几百 MB），
      // 然后才检查 content-type、发现是 video/mp4 再丢掉 ——
      // 既慢得要命，也可能直接把应用撑爆。
      //
      // `send()` 只返回响应头，正文由我们自己按需读。
      final http.Response resp = await NetError.retry(
        () async {
          final http.Client client = http.Client();
          try {
            final http.Request req = http.Request('GET', uri)
              ..headers.addAll(<String, String>{
                'User-Agent': WebViewLoader.mobileUserAgent,
                'Accept': 'text/html,application/json,text/plain,*/*;q=0.8',
              });
            final http.StreamedResponse sr =
                await client.send(req).timeout(timeout);
            return _readCapped(sr);
          } finally {
            client.close();
          }
        },
        // **只试一次。**
        //
        // 原来是 2 次，理由是"瞬时中断重试一下通常就过了"。但 fetch 是
        // 交互操作 —— 用户正盯着转圈等结果，而重试会把等待**直接翻倍**
        // （15 秒变 30 秒）。真遇到瞬时故障，下面的 WebView 兜底还有一次机会，
        // 不值得在这里让用户多等一倍。
        attempts: 1,
      );

      final String ct =
          (resp.headers['content-type'] ?? '').toLowerCase();

      // 二进制内容（视频/音频/图片/压缩包…）到此为止。
      // 正文已经在 _readCapped 里被拦下、根本没读进内存，
      // 这里给出明确原因 —— 否则会继续走到 WebView 兜底，
      // 那边会尝试去"渲染"一个视频，纯属浪费。
      if (_isBinary(ct)) {
        return WebContent(
          url: uri.toString(),
          error: '这是 $ct 内容（视频/音频/图片等二进制文件），不是网页，抓不到文本。',
        );
      }

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
        // **必须显式传**。不传就用 WebViewLoader 的默认值 35 秒 ——
        // 加上前面的 HTTP 直连（15 秒）和 WebView 创建（12 秒），
        // 最坏情况要等 60 多秒。抓一个网页不值得让用户等这么久。
        timeout: const Duration(seconds: 18),
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

  // ------------------------------------------------------- 读取保护

  /// 抓取上限。超过就不再往内存里读 ——
  /// 我们要的是网页正文，不是文件下载。
  static const int _maxBytes = 2 * 1024 * 1024; // 2 MB

  /// 把流式响应读成 [http.Response]，但**先看响应头再决定读不读正文**。
  ///
  /// 这是防"抓视频"事故的关键：
  /// · 二进制类型 → 一个字节都不读，直接返回空体；
  /// · content-length 声称过大 → 同样不读；
  /// · 没给 content-length 的分块响应 → 边读边计数，到上限就停。
  static Future<http.Response> _readCapped(http.StreamedResponse sr) async {
    final String ct = (sr.headers['content-type'] ?? '').toLowerCase();

    if (_isBinary(ct)) {
      return http.Response('', sr.statusCode, headers: sr.headers);
    }

    final int? len = sr.contentLength;
    if (len != null && len > _maxBytes) {
      return http.Response('', sr.statusCode, headers: sr.headers);
    }

    final BytesBuilder bb = BytesBuilder(copy: false);
    await for (final List<int> chunk in sr.stream) {
      bb.add(chunk);
      if (bb.length > _maxBytes) break;
    }
    return http.Response.bytes(
      bb.takeBytes(),
      sr.statusCode,
      headers: sr.headers,
    );
  }

  /// 是不是二进制内容（不该当网页抓的）
  static bool _isBinary(String ct) {
    if (ct.isEmpty) return false;
    const List<String> markers = <String>[
      'video/',
      'audio/',
      'image/',
      'font/',
      'multipart/',
      'application/octet-stream',
      'application/zip',
      'application/pdf',
      'application/x-',
    ];
    for (final String m in markers) {
      if (ct.contains(m)) return true;
    }
    return false;
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
