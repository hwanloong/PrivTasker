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

  /// 探活，给设置页的「测试连接」用
  static Future<String?> health(String baseUrl) async {
    final Uri? uri = _endpoint(baseUrl, '/health');
    if (uri == null) return '地址不合法';
    try {
      final http.Response resp =
          await http.get(uri).timeout(const Duration(seconds: 10));
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
    Duration timeout = const Duration(seconds: 45),
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

    try {
      final http.Response resp = await NetError.retry(
        () => http
            .post(
              uri,
              headers: <String, String>{'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(timeout),
        attempts: 2,
      );

      if (resp.statusCode != 200) {
        return SelfHostedOutcome(
          ok: false,
          error: 'HTTP ${resp.statusCode}：${_humanize(resp.bodyBytes)}',
        );
      }

      return parseResponse(utf8.decode(resp.bodyBytes), topK: topK);
    } catch (e) {
      return SelfHostedOutcome(ok: false, error: NetError.describe(e));
    }
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
