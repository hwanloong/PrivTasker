import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/net_error.dart';
import '../core/store.dart';

/// 模型请求调用某个工具
class ToolCallRequest {
  ToolCallRequest({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;

  /// 原始 JSON 字符串（回传时必须原样带上）
  final String arguments;
}

/// 一轮 assistant 回复
class AssistantTurn {
  AssistantTurn({
    this.content = '',
    this.reasoning = '',
    this.toolCalls = const <ToolCallRequest>[],
    this.promptTokens,
    this.completionTokens,
    this.reasoningTokens,
  });

  final String content;

  /// deepseek-reasoner 的思维链，普通模型为空
  final String reasoning;
  final List<ToolCallRequest> toolCalls;

  /// API 实测返回的 token 用量。为 null 表示服务端没给，
  /// 调用方只能本地估算 —— 这两者在 UI 上必须区分显示。
  final int? promptTokens;
  final int? completionTokens;
  final int? reasoningTokens;

  bool get hasUsage => promptTokens != null || completionTokens != null;

  bool get hasToolCalls => toolCalls.isNotEmpty;
}

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => statusCode == null ? message : 'HTTP $statusCode: $message';
}

/// DeepSeek（OpenAI 兼容）客户端。
class DeepSeekClient {
  DeepSeekClient(this.settings);

  final Settings settings;
  http.Client? _client;

  /// 置为 true 可让进行中的流式请求尽快停下
  bool cancelled = false;

  void cancel() {
    cancelled = true;
    _client?.close();
    _client = null;
  }

  /// 发一轮对话请求。[onText] 会在流式过程中被反复调用。
  Future<AssistantTurn> chat({
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools = const <Map<String, dynamic>>[],
    void Function(String text)? onText,
    void Function(String reasoning)? onReasoning,
  }) async {
    if (!settings.configured) {
      throw ApiException('还没有填 API Key，请到设置里填写 DeepSeek API Key');
    }

    cancelled = false;

    // 一旦已经流出内容，就不能重试了 —— 重试会把前面的内容再输出一遍，
    // 用户会看到重复的段落。所以只在整个响应还"干净"的时候才重试。
    bool receivedAnything = false;

    try {
      return await NetError.retry(
        () => _attempt(
          messages: messages,
          tools: tools,
          onText: (String t) {
            receivedAnything = true;
            onText?.call(t);
          },
          onReasoning: (String r) {
            receivedAnything = true;
            onReasoning?.call(r);
          },
        ),
        attempts: 3,
        shouldRetry: (Object _) => !receivedAnything && !cancelled,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      if (cancelled) return AssistantTurn(content: '');
      // 把 ECONNABORTED 这类底层 errno 文案翻译成人话
      throw ApiException(NetError.describe(e));
    }
  }

  Future<AssistantTurn> _attempt({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    required void Function(String text) onText,
    required void Function(String reasoning) onReasoning,
  }) async {
    final http.Client client = http.Client();
    _client = client;

    final Map<String, dynamic> payload = <String, dynamic>{
      'model': settings.model,
      'messages': messages,
      'stream': true,
      // 请求在流末尾附带 usage（OpenAI 兼容字段）。
      // 服务端不支持时会被静默忽略，那就拿不到实测值，
      // 调用方会退回本地估算 —— 不会因此报错。
      'stream_options': <String, dynamic>{'include_usage': true},
    };

    if (settings.thinkingEnabled) {
      // 思考模式：temperature / presence_penalty / frequency_penalty
      // 官方明确说明「设置不报错但也不生效」，索性不发，免得造成误导。
      payload['thinking'] = <String, dynamic>{'type': 'enabled'};
      payload['reasoning_effort'] = settings.reasoningEffort;
    } else {
      payload['thinking'] = <String, dynamic>{'type': 'disabled'};
      payload['temperature'] = settings.temperature;
    }

    if (tools.isNotEmpty) {
      payload['tools'] = tools;
      payload['tool_choice'] = 'auto';
    }

    try {
      final http.Request req =
          http.Request('POST', Uri.parse(settings.chatEndpoint));
      req.headers.addAll(<String, String>{
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'Authorization': 'Bearer ${settings.apiKey}',
      });
      req.body = jsonEncode(payload);

      final http.StreamedResponse resp =
          await client.send(req).timeout(const Duration(seconds: 60));

      if (resp.statusCode != 200) {
        final String body = await resp.stream
            .bytesToString()
            .timeout(const Duration(seconds: 20));
        // 带状态码的错误不重试：401/400/402 重试多少次都一样
        throw ApiException(_humanize(body), statusCode: resp.statusCode);
      }

      return await _consumeStream(resp, onText, onReasoning);
    } finally {
      _client = null;
      client.close();
    }
  }

  /// 解析 SSE 流。
  ///
  /// 这里有两个必须处理对的点：
  ///  1. `data:` 里可能是空行、注释行、`[DONE]`，都要跳过；
  ///  2. **tool_calls 是按 index 分片下发的**——第一片只有 id 和 name，
  ///     后续片只带 arguments 的片段。必须按 index 累加拼接，
  ///     否则会拿到被截断的 JSON 参数。
  Future<AssistantTurn> _consumeStream(
    http.StreamedResponse resp,
    void Function(String)? onText,
    void Function(String)? onReasoning,
  ) async {
    final StringBuffer content = StringBuffer();
    final StringBuffer reasoning = StringBuffer();
    final Map<int, _ToolAcc> acc = <int, _ToolAcc>{};

    int? usagePrompt;
    int? usageCompletion;
    int? usageReasoning;

    final Stream<String> lines = resp.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final String rawLine in lines) {
      if (cancelled) break;

      final String line = rawLine.trim();
      if (line.isEmpty || !line.startsWith('data:')) continue;

      final String data = line.substring(5).trim();
      if (data == '[DONE]') break;
      if (data.isEmpty) continue;

      Map<String, dynamic> chunk;
      try {
        chunk = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        continue; // 半截 JSON 或心跳，跳过
      }

      if (chunk['error'] != null) {
        throw ApiException(_humanize(jsonEncode(chunk['error'])));
      }

      // 用量在最后一个 chunk 里，而那个 chunk 的 choices 通常是空数组，
      // 会在下面被 continue 跳过 —— 所以必须在这之前取。
      final dynamic usage = chunk['usage'];
      if (usage is Map) {
        usagePrompt =
            (usage['prompt_tokens'] as num?)?.toInt() ?? usagePrompt;
        usageCompletion =
            (usage['completion_tokens'] as num?)?.toInt() ?? usageCompletion;
        final dynamic details = usage['completion_tokens_details'];
        if (details is Map) {
          usageReasoning =
              (details['reasoning_tokens'] as num?)?.toInt() ?? usageReasoning;
        }
      }

      final List<dynamic> choices =
          (chunk['choices'] as List<dynamic>?) ?? <dynamic>[];
      if (choices.isEmpty) continue;

      final Map<String, dynamic> choice =
          Map<String, dynamic>.from(choices.first as Map);
      final Map<String, dynamic>? delta = choice['delta'] == null
          ? null
          : Map<String, dynamic>.from(choice['delta'] as Map);
      if (delta == null) continue;

      final dynamic c = delta['content'];
      if (c is String && c.isNotEmpty) {
        content.write(c);
        onText?.call(c);
      }

      final dynamic rc = delta['reasoning_content'];
      if (rc is String && rc.isNotEmpty) {
        reasoning.write(rc);
        onReasoning?.call(rc);
      }

      final List<dynamic>? tc = delta['tool_calls'] as List<dynamic>?;
      if (tc != null) {
        for (final dynamic item in tc) {
          final Map<String, dynamic> t = Map<String, dynamic>.from(item as Map);
          final int index = (t['index'] as num?)?.toInt() ?? 0;
          final _ToolAcc a = acc.putIfAbsent(index, () => _ToolAcc());

          final dynamic id = t['id'];
          if (id is String && id.isNotEmpty) a.id = id;

          final dynamic fn = t['function'];
          if (fn is Map) {
            final Map<String, dynamic> f = Map<String, dynamic>.from(fn);
            final dynamic name = f['name'];
            if (name is String && name.isNotEmpty) a.name = name;
            final dynamic argsFrag = f['arguments'];
            if (argsFrag is String) a.arguments.write(argsFrag);
          }
        }
      }
    }

    final List<ToolCallRequest> calls = acc.entries
        .where((MapEntry<int, _ToolAcc> e) => e.value.name.isNotEmpty)
        .map((MapEntry<int, _ToolAcc> e) => ToolCallRequest(
              id: e.value.id.isEmpty
                  ? 'call_${e.key}_${DateTime.now().microsecondsSinceEpoch}'
                  : e.value.id,
              name: e.value.name,
              arguments: e.value.arguments.toString().trim().isEmpty
                  ? '{}'
                  : e.value.arguments.toString(),
            ))
        .toList();

    return AssistantTurn(
      content: content.toString(),
      reasoning: reasoning.toString(),
      toolCalls: calls,
      promptTokens: usagePrompt,
      completionTokens: usageCompletion,
      reasoningTokens: usageReasoning,
    );
  }

  /// 把 API 的错误 JSON 变成人话
  static String _humanize(String body) {
    try {
      final dynamic j = jsonDecode(body);
      if (j is Map) {
        final dynamic err = j['error'];
        if (err is Map && err['message'] != null) {
          return err['message'].toString();
        }
        if (j['message'] != null) return j['message'].toString();
      }
    } catch (_) {}
    return body.length > 400 ? '${body.substring(0, 400)}…' : body;
  }
}

class _ToolAcc {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
}
