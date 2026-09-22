import 'dart:async';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 无头 WebView 加载器。
///
/// `browser` 工具和「网页链接」附件抓取都用它，避免两处各写一份
/// 生命周期管理（那很容易一边修好另一边还留着 bug）。
///
/// 核心是**轮询**而不是「等固定时长再抽一次」：结果页多是 JS 异步渲染的，
/// 固定等待要么不够（抽到空）要么白等。这里每隔一段时间重试，
/// 直到 [isDone] 为真、或尝试次数用尽（此时把最后一次结果交出去，供上层诊断）。
class WebViewLoader {
  const WebViewLoader._();

  /// 移动端 UA。用桌面 UA 有些站点会返回不同（更重）的页面。
  static const String mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0 Mobile Safari/537.36';

  /// 打开 [url]，反复执行 [js] 直到 [isDone] 为真或尝试次数用尽。
  /// 返回 null 表示主文档加载失败或整体超时。
  static Future<String?> load({
    required String url,
    required String js,
    bool Function(String value)? isDone,
    int attempts = 6,
    Duration timeout = const Duration(seconds: 35),
  }) async {
    HeadlessInAppWebView? headless;
    final Completer<String?> completer = Completer<String?>();

    void finish(String? value) {
      if (!completer.isCompleted) completer.complete(value);
    }

    try {
      headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          transparentBackground: true,
          mediaPlaybackRequiresUserGesture: true,
          // 不加载图片：抓文本不需要，能明显加快加载
          blockNetworkImage: true,
          useShouldInterceptRequest: false,
          // 开启缓存。搜索引擎的 CSS/JS/字体第一次下完就留在本地，
          // 之后再抓同一个引擎几乎不用重新下载 —— 这是最省事的一处提速。
          cacheEnabled: true,
          clearCache: false,
        ),
        onLoadStop: (InAppWebViewController controller, WebUri? uri) async {
          if (completer.isCompleted) return;

          String? last;
          for (int i = 0; i < attempts; i++) {
            try {
              // 第一次立刻抽，不要先等。
              // 原来固定先等 900ms，等于每次加载白扔将近一秒 ——
              // 而多数静态页面在 onLoadStop 时内容已经就绪了。
              if (i > 0) {
                await Future<void>.delayed(_pollDelay(i));
              }
              if (completer.isCompleted) return;

              final dynamic r = await controller.evaluateJavascript(source: js);
              final String? s = r?.toString();
              if (s == null) continue;

              last = s;
              if (isDone == null || isDone(s)) {
                finish(s);
                return;
              }
            } catch (_) {
              // 单次抽取失败就继续重试
            }
          }
          finish(last);
        },
        onReceivedError: (
          InAppWebViewController controller,
          WebResourceRequest request,
          WebResourceError error,
        ) {
          // 只有主文档失败才算失败；子资源（图片/广告）失败不影响
          if (request.isForMainFrame == true) finish(null);
        },
      );

      await headless.run();
      return await completer.future.timeout(timeout);
    } catch (_) {
      return null;
    } finally {
      try {
        await headless?.dispose();
      } catch (_) {
        // 忽略清理失败
      }
    }
  }

  /// 自适应的轮询间隔。
  ///
  /// 前面密、后面疏：内容大多在头几百毫秒内就绪，先密集探测能立刻拿到；
  /// 真遇到慢页面时再拉长间隔，避免空转浪费。
  /// 累计等待约 0.2 + 0.35 + 0.55 + 0.85 + 1.2 ≈ 3.2 秒，
  /// 比原来固定 6 × 900ms = 5.4 秒短得多，而且能更早命中。
  static Duration _pollDelay(int attempt) {
    const List<int> ms = <int>[200, 350, 550, 850, 1200];
    final int idx = attempt - 1;
    return Duration(
      milliseconds: idx < ms.length ? ms[idx] : ms.last,
    );
  }

  /// evaluateJavascript 在部分平台会把字符串结果再包一层引号并转义，
  /// 这里尝试还原成可直接 jsonDecode 的文本。
  static String unwrapJsString(String raw) {
    String s = raw.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      try {
        final dynamic decoded = jsonDecode(s);
        if (decoded is String) s = decoded;
      } catch (_) {
        // 保持原样
      }
    }
    return s;
  }

  /// 提取正文：去掉脚本/样式/内嵌框架后取可见文本
  static const String extractTextJs = r'''
(function () {
  if (!document.body) return '';
  var c = document.body.cloneNode(true);
  ['script', 'style', 'noscript', 'svg', 'iframe', 'template'].forEach(function (tag) {
    c.querySelectorAll(tag).forEach(function (n) { n.remove(); });
  });
  var t = c.innerText || c.textContent || '';
  t = t.replace(/[ \t\u00A0]+/g, ' ');
  t = t.replace(/\n\s*\n\s*\n+/g, '\n\n');
  return t.trim().slice(0, 30000);
})()
''';

  /// 提取标题 + 正文，用于网页附件
  static const String extractPageJs = r'''
(function () {
  var t = '';
  if (document.body) {
    var c = document.body.cloneNode(true);
    ['script', 'style', 'noscript', 'svg', 'iframe', 'template'].forEach(function (tag) {
      c.querySelectorAll(tag).forEach(function (n) { n.remove(); });
    });
    t = c.innerText || c.textContent || '';
    t = t.replace(/[ \t\u00A0]+/g, ' ');
    t = t.replace(/\n\s*\n\s*\n+/g, '\n\n');
    t = t.trim().slice(0, 30000);
  }
  return JSON.stringify({
    title: document.title || '',
    url: location.href,
    text: t
  });
})()
''';
}
