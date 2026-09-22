import 'dart:convert';

import 'package:http/http.dart' as http;

import 'net_error.dart';

/// 一次服务端搜索的结果
class ServerSearchOutcome {
  const ServerSearchOutcome({
    required this.searched,
    this.text = '',
    this.error,
  });

  /// **是否真的执行了服务端搜索**。
  ///
  /// 这个字段是整个设计的核心：DeepSeek 官方文档把 `web_search` 列为
  /// 「忽略」，但它又提到 `web_search_call` item 会被还原拼接。
  /// 所以不能看模型说了什么就当成搜到了 —— 必须检查响应里
  /// 有没有真的出现 `web_search_call`。
  /// 没搜到却把模型的自由发挥当成搜索结果展示，是更糟的结果。
  final bool searched;

  final String text;
  final String? error;
}

/// 走 DeepSeek Responses API 的服务端联网搜索。
///
/// 相比内置浏览器抓取，这条路的优势是不受反爬影响、也不用等页面渲染。
/// 但目前**能否生效存疑**：官方 Tools 表把 `web_search` 标为「忽略」。
/// 所以这里不假设它一定成功，而是检测响应里是否真的产生了搜索调用，
/// 让调用方决定要不要降级到别的通道。
class DeepSeekServerSearch {
  const DeepSeekServerSearch._();

  static Future<ServerSearchOutcome> search({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String query,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (apiKey.trim().isEmpty) {
      return const ServerSearchOutcome(
        searched: false,
        error: '没有可用的 API Key',
      );
    }

    final String base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final Uri uri;
    try {
      // 注意是 /responses，不是 /chat/completions
      uri = Uri.parse('${base.isEmpty ? 'https://api.deepseek.com' : base}/responses');
    } catch (_) {
      return const ServerSearchOutcome(searched: false, error: '接口地址不合法');
    }

    try {
      final http.Response resp = await NetError.retry(
        () => http
            .post(
              uri,
              headers: <String, String>{
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $apiKey',
              },
              body: jsonEncode(<String, dynamic>{
                'model': model,
                'instructions': '请使用联网搜索获取最新信息，'
                    '并在回答中标注信息来源。不要凭记忆回答时效性内容。',
                'input': query,
                'tools': <Map<String, dynamic>>[
                  <String, dynamic>{'type': 'web_search'},
                ],
                'tool_choice': 'auto',
                'max_output_tokens': 2000,
              }),
            )
            .timeout(timeout),
        attempts: 2,
      );

      if (resp.statusCode != 200) {
        return ServerSearchOutcome(
          searched: false,
          error: 'HTTP ${resp.statusCode}：${_humanize(resp.bodyBytes)}',
        );
      }

      return parseResponse(utf8.decode(resp.bodyBytes));
    } catch (e) {
      return ServerSearchOutcome(searched: false, error: NetError.describe(e));
    }
  }

  /// 解析 Responses API 的返回。
  ///
  /// 抽成独立方法是为了能单独测：**「到底有没有真的搜索」这个判断一旦错，
  /// 就会把模型凭记忆编的内容当成搜索结果展示给用户** —— 那比搜不到更糟。
  static ServerSearchOutcome parseResponse(String body) {
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      return ServerSearchOutcome(
        searched: false,
        error: '返回不是合法 JSON：$e',
      );
    }

    final List<dynamic> output = (j['output'] as List<dynamic>?) ?? <dynamic>[];

    // 关键判断：响应里有没有真的出现搜索调用
    final List<Map> searchCalls = output
        .whereType<Map>()
        .where((Map e) => e['type'] == 'web_search_call')
        .toList();

    final String text = extractText(j, output);

    if (searchCalls.isEmpty) {
      return ServerSearchOutcome(
        searched: false,
        text: text,
        error: '服务端没有执行搜索（响应里没有 web_search_call）。'
            '官方文档把 web_search 标为「忽略」，这条通道目前很可能不生效。',
      );
    }

    return ServerSearchOutcome(searched: true, text: text);
  }

  /// 取输出文本。`output_text` 是便利字段，但不同实现未必都带，
  /// 所以再从 message item 里兜一层。
  static String extractText(
    Map<String, dynamic> root,
    List<dynamic> output,
  ) {
    final String direct = root['output_text']?.toString() ?? '';
    if (direct.trim().isNotEmpty) return direct.trim();

    final StringBuffer sb = StringBuffer();
    for (final dynamic item in output) {
      if (item is! Map) continue;
      if (item['type'] != 'message') continue;
      final List<dynamic> content =
          (item['content'] as List<dynamic>?) ?? <dynamic>[];
      for (final dynamic c in content) {
        if (c is! Map) continue;
        final String t = c['text']?.toString() ?? '';
        if (t.trim().isNotEmpty) {
          if (sb.isNotEmpty) sb.writeln();
          sb.write(t.trim());
        }
      }
    }
    return sb.toString().trim();
  }

  static String _humanize(List<int> bodyBytes) {
    final String body = utf8.decode(bodyBytes, allowMalformed: true);
    try {
      final dynamic j = jsonDecode(body);
      if (j is Map) {
        final dynamic err = j['error'];
        if (err is Map && err['message'] != null) {
          return err['message'].toString();
        }
        if (j['message'] != null) return j['message'].toString();
      }
    } catch (_) {
      // 不是 JSON，原样截断
    }
    return body.length > 300 ? '${body.substring(0, 300)}…' : body.trim();
  }
}
