import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'net_error.dart';
import 'scrub.dart';

/// 一次自建搜索的结果
class SelfHostedOutcome {
  const SelfHostedOutcome({required this.ok, this.text = '', this.error});

  final bool ok;
  final String text;
  final String? error;
}

/// agent-web-search 这类**自建搜索服务**的客户端。
///
/// 接口约定（POST /search）：
///   {"query": "...", "include_content": true, "render_js": false,
///    "categories": ["it"|"news"|"general"], "time_range": "day"|...}
///
/// 返回两种形态，都要兼容：
///   include_content=true  → {"ranked_chunks":[{text,parent_text,score,source}],
///                            "unresponsive_engines":[]}
///   include_content=false → {"results":[{url,title,score}]}
///
/// 这类服务相比直接抓搜索引擎的价值在于它做了**抓取 → 正文提取 → 去噪 →
/// 分块 → 向量化 → 按相关度排序**这一整条链，拿回来的就是能直接读的资料；
/// 而且它自己带提示注入清洗。
///
/// 注意它是**独立部署的服务**（Docker + SearXNG），不在手机上跑 ——
/// 所以这里只是一个 HTTP 客户端，地址由用户在设置里填。
class SelfHostedSearch {
  const SelfHostedSearch._();

  /// 探活。
  ///
  /// 有两个用途：
  ///  1. 设置页的「测试连接」
  ///  2. **搜索前的预检** —— 这个更重要。搜索接口很慢（服务端要加载嵌入模型、
  ///     还要抓取+提取+分块+排序），拿 40 秒去赌一个可能根本没启动的服务
  ///     是最糟的体验。`/health` 是空操作，几秒就能判断，不通就直接跳过这一层。
  static Future<String?> health(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final Uri? uri = _endpoint(baseUrl, '/health');
    if (uri == null) return '地址不合法';
    try {
      final http.Response resp = await http.get(uri).timeout(timeout);
      if (resp.statusCode != 200) return 'HTTP ${resp.statusCode}';
      final dynamic j = jsonDecode(utf8.decode(resp.bodyBytes));
      if (j is Map && j['status'] != null) return null; // 正常
      return '返回格式不是预期的 {"status": ...}';
    } catch (e) {
      return NetError.describe(e);
    }
  }

  static Uri? _endpoint(String baseUrl, String path) {
    final String base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return null;
    try {
      final Uri? b = Uri.tryParse(base);
      if (b == null || !b.hasScheme) return null;
      return Uri.parse('$base$path');
    } catch (_) {
      return null;
    }
  }

  static Future<SelfHostedOutcome> search({
    required String baseUrl,
    required String query,
    int topK = 3,
    bool includeContent = true,
    String? category,
    Duration timeout = const Duration(seconds: 35),
  }) async {
    final Uri? uri = _endpoint(baseUrl, '/search');
    if (uri == null) {
      return const SelfHostedOutcome(ok: false, error: '自建搜索地址不合法');
    }

    final Map<String, dynamic> payload = <String, dynamic>{
      'query': query,
      'include_content': includeContent,
      'render_js': false,
    };
    if (category != null && category.trim().isNotEmpty) {
      payload['categories'] = <String>[category.trim()];
    }

    // 重试策略：**只在超时时重试一次**。
    //
    // 这个服务第一次搜索要加载嵌入模型（sentence-transformers 是懒加载的），
    // 冷启动可能超过单次超时 —— 表现就是「一直转圈然后失败」。
    // 但第一次超时的那一刻，服务端其实已经把模型装进内存了（它还在继续跑），
    // 所以紧接着再发一次通常秒回。
    //
    // 这里修正了我上一轮的错误判断：当时我删掉重试，理由是「重试只是把等待翻倍」。
    // 那对「服务真的挂了」成立，但对「冷启动」恰恰相反 —— 不重试就永远失败，
    // 而且用户会以为服务坏了。
    //
    // 只对超时重试，不对其它错误重试：连接被拒、HTTP 4xx 再试也是一样的结果。
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final http.Response resp = await http
            .post(
              uri,
              headers: <String, String>{'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(timeout);

        if (resp.statusCode != 200) {
          return SelfHostedOutcome(
            ok: false,
            error: 'HTTP ${resp.statusCode}：${_humanize(resp.bodyBytes)}',
          );
        }

        return parseResponse(utf8.decode(resp.bodyBytes), topK: topK);
      } on TimeoutException {
        if (attempt == 0) {
          // 冷启动，模型这会儿应该已经加载好了，再试一次
          continue;
        }
        return SelfHostedOutcome(
          ok: false,
          error: '两次请求都超时（每次 ${timeout.inSeconds} 秒）。'
              '服务端可能仍在加载模型，或正在处理别的请求 —— 稍等几秒再问一次，'
              '通常就快了（模型加载进内存后会一直留着）。',
        );
      } catch (e) {
        return SelfHostedOutcome(ok: false, error: NetError.describe(e));
      }
    }

    return const SelfHostedOutcome(ok: false, error: '未知错误');
  }

  /// 解析返回。抽成独立方法以便单测 —— 两种响应形态都要兼容。
  static SelfHostedOutcome parseResponse(String body, {int topK = 3}) {
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      return SelfHostedOutcome(ok: false, error: '返回不是合法 JSON：$e');
    }

    final List<dynamic> chunks =
        (j['ranked_chunks'] as List<dynamic>?) ?? <dynamic>[];
    final List<dynamic> results =
        (j['results'] as List<dynamic>?) ?? <dynamic>[];

    final StringBuffer sb = StringBuffer();
    int n = 0;

    // ---- 形态一：带内容的 ranked_chunks ----
    for (final dynamic item in chunks) {
      if (n >= topK) break;
      if (item is! Map) continue;
      n++;

      final Map<String, dynamic> c = Map<String, dynamic>.from(item);
      final Map<String, dynamic> src = c['source'] is Map
          ? Map<String, dynamic>.from(c['source'] as Map)
          : <String, dynamic>{};

      final String title = (src['title'] ?? '').toString().trim();
      final String url = (src['url'] ?? '').toString().trim();
      final double score = (c['score'] as num?)?.toDouble() ?? 0;

      // parent_text 是给 LLM 读的 512-token 窗口；text 是给向量用的 256-token 片段。
      // 我们要喂给模型，所以优先用 parent_text。
      final String parent = (c['parent_text'] ?? '').toString().trim();
      final String text = (c['text'] ?? '').toString().trim();
      final String content = parent.isNotEmpty ? parent : text;

      sb.writeln('[$n] ${title.isEmpty ? url : title}');
      if (url.isNotEmpty) sb.writeln('    来源：$url');
      sb.writeln('    相关度：${score.toStringAsFixed(3)}');
      if (content.isNotEmpty) {
        final ScrubResult cleaned = PromptScrubber.scrub(content);
        sb.writeln('    内容：');
        sb.writeln(cleaned.text);
        if (!cleaned.clean) {
          sb.writeln('    ⚠ ${cleaned.summary}');
        }
      }
      sb.writeln();
    }

    // ---- 形态二：只有链接的 results ----
    if (n == 0) {
      for (final dynamic item in results) {
        if (n >= topK) break;
        if (item is! Map) continue;
        n++;

        final Map<String, dynamic> r = Map<String, dynamic>.from(item);
        final String title = (r['title'] ?? '').toString().trim();
        final String url = (r['url'] ?? '').toString().trim();
        final String snippet = (r['snippet'] ?? '').toString().trim();
        final double score = (r['score'] as num?)?.toDouble() ?? 0;

        sb.writeln('[$n] ${title.isEmpty ? url : title}');
        if (url.isNotEmpty) sb.writeln('    来源：$url');
        if (score > 0) sb.writeln('    相关度：${score.toStringAsFixed(3)}');
        if (snippet.isNotEmpty) {
          sb.writeln('    摘要：${PromptScrubber.scrub(snippet).text}');
        }
        sb.writeln();
      }
    }

    if (n == 0) {
      final List<dynamic> bad =
          (j['unresponsive_engines'] as List<dynamic>?) ?? <dynamic>[];
      return SelfHostedOutcome(
        ok: false,
        error: bad.isEmpty
            ? '服务返回了空结果'
            : '服务返回空结果；无响应的引擎：${bad.join('、')}',
      );
    }

    final List<dynamic> bad =
        (j['unresponsive_engines'] as List<dynamic>?) ?? <dynamic>[];
    final String note =
        bad.isEmpty ? '' : '\n（无响应的引擎：${bad.join('、')}）';

    return SelfHostedOutcome(
      ok: true,
      text: '（来源：自建搜索服务）\n\n$sb$note',
    );
  }

  static String _humanize(List<int> bodyBytes) {
    final String body = utf8.decode(bodyBytes, allowMalformed: true);
    try {
      final dynamic j = jsonDecode(body);
      if (j is Map) {
        final dynamic d = j['detail'];
        if (d != null) {
          return d is String ? d : jsonEncode(d);
        }
        if (j['message'] != null) return j['message'].toString();
      }
    } catch (_) {
      // 不是 JSON
    }
    return body.length > 300 ? '${body.substring(0, 300)}…' : body.trim();
  }
}
