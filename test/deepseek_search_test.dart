import 'package:dsh_agent/core/deepseek_search.dart';
import 'package:flutter_test/flutter_test.dart';

/// 这里测的是整套服务端搜索里**最关键、也最容易搞错的一步**：
/// 判断响应到底有没有真的执行搜索。
///
/// 背景：DeepSeek 官方把 `web_search` 列为「忽略」，但实际上可能生效。
/// 如果只看到模型输出了文字就当成搜索结果，它凭记忆编的内容就会被
/// 当成"联网查到的东西"展示 —— 那比搜不到更糟。所以必须看
/// 响应里有没有 `web_search_call`。
void main() {
  group('判断是否真的执行了搜索', () {
    test('有 web_search_call 才算搜到', () {
      const String body = '''
      {
        "output": [
          {"type": "web_search_call", "id": "ws_1", "status": "completed"},
          {"type": "message", "content": [
            {"type": "output_text", "text": "根据搜索结果，DeepSeek V4 于 2026 年发布。"}
          ]}
        ]
      }
      ''';
      final ServerSearchOutcome r = DeepSeekServerSearch.parseResponse(body);
      expect(r.searched, isTrue);
      expect(r.text, contains('DeepSeek V4'));
      expect(r.error, isNull);
    });

    test('没有 web_search_call 就是没搜 —— 哪怕模型写了一堆内容', () {
      const String body = '''
      {
        "output": [
          {"type": "message", "content": [
            {"type": "output_text", "text": "我记得 DeepSeek 最新模型是 V3。"}
          ]}
        ]
      }
      ''';
      final ServerSearchOutcome r = DeepSeekServerSearch.parseResponse(body);
      // 关键：文本照样带出来，但绝不能标成「搜到了」
      expect(r.searched, isFalse);
      expect(r.error, isNotNull);
      expect(r.error, contains('web_search_call'));
      expect(r.text, contains('V3'));
    });

    test('多个搜索调用也只算搜到一次', () {
      const String body = '''
      {
        "output": [
          {"type": "web_search_call", "id": "ws_1"},
          {"type": "web_search_call", "id": "ws_2"},
          {"type": "message", "content": [{"type": "output_text", "text": "结果"}]}
        ]
      }
      ''';
      expect(DeepSeekServerSearch.parseResponse(body).searched, isTrue);
    });
  });

  group('取输出文本', () {
    test('优先用 output_text 便利字段', () {
      const String body = '''
      {"output_text": "直接给的文本", "output": []}
      ''';
      expect(DeepSeekServerSearch.parseResponse(body).text, '直接给的文本');
    });

    test('没有 output_text 时从 message item 里拼', () {
      const String body = '''
      {
        "output": [
          {"type": "message", "content": [
            {"type": "output_text", "text": "第一段"},
            {"type": "output_text", "text": "第二段"}
          ]}
        ]
      }
      ''';
      final String t = DeepSeekServerSearch.parseResponse(body).text;
      expect(t, contains('第一段'));
      expect(t, contains('第二段'));
    });

    test('空 output 不炸', () {
      expect(DeepSeekServerSearch.parseResponse('{}').text, '');
      expect(DeepSeekServerSearch.parseResponse('{"output": []}').searched, isFalse);
    });
  });

  group('异常输入', () {
    test('返回不是 JSON 时给出明确错误，而不是抛异常', () {
      final ServerSearchOutcome r =
          DeepSeekServerSearch.parseResponse('<html>502 Bad Gateway</html>');
      expect(r.searched, isFalse);
      expect(r.error, contains('合法 JSON'));
    });
  });
}
