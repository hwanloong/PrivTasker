import 'package:dsh_agent/core/net_error.dart';
import 'package:flutter_test/flutter_test.dart';

/// 造一个长得像 SocketException 的异常。
/// 真实异常来自 dart:io，在测试里不方便构造，但 toString 的形状是一致的。
class _FakeException implements Exception {
  _FakeException(this.text);
  final String text;
  @override
  String toString() => text;
}

void main() {
  group('翻译成人话', () {
    test('ECONNABORTED 会给出原因和处置建议', () {
      final String msg = NetError.describe(_FakeException(
        'ClientException with SocketException: Software caused connection abort '
        '(OS Error: Software caused connection abort, errno = 103), '
        'uri=https://api.deepseek.com/chat/completions',
      ));
      expect(msg, contains('ECONNABORTED'));
      // 必须说清「可能是什么原因」和「该怎么办」，只报错名等于没报
      expect(msg, contains('WiFi'));
      expect(msg, contains('重试'));
    });

    test('常见错误各有对应说明', () {
      expect(
        NetError.describe(_FakeException('SocketException: Connection reset by peer')),
        contains('ECONNRESET'),
      );
      expect(
        NetError.describe(_FakeException('SocketException: Failed host lookup: nope.invalid')),
        contains('域名解析失败'),
      );
      expect(
        NetError.describe(_FakeException('SocketException: Network is unreachable')),
        contains('网络不可达'),
      );
      expect(
        NetError.describe(_FakeException('HttpException: Connection refused')),
        contains('连接被拒绝'),
      );
    });

    test('认不出来的错误原样返回，不编造解释', () {
      const String weird = 'Something entirely unexpected';
      expect(NetError.describe(_FakeException(weird)), weird);
    });
  });

  group('是否值得重试', () {
    test('瞬时故障要重试', () {
      for (final String s in <String>[
        'Software caused connection abort',
        'Connection reset by peer',
        'Broken pipe',
        'TimeoutException after 0:00:20',
        'The connection attempt failed',
      ]) {
        expect(NetError.isTransient(_FakeException(s)), isTrue, reason: s);
      }
    });

    test('重试也没用的不重试', () {
      for (final String s in <String>[
        'Failed host lookup: nope.invalid',
        'Certificate verify failed',
        'Connection refused',
      ]) {
        expect(NetError.isTransient(_FakeException(s)), isFalse, reason: s);
      }
    });
  });

  group('重试策略', () {
    test('瞬时错误会重试并最终成功', () async {
      int calls = 0;
      final String result = await NetError.retry<String>(
        () async {
          calls++;
          if (calls < 3) {
            throw _FakeException('Software caused connection abort');
          }
          return 'ok';
        },
        attempts: 3,
        baseDelay: const Duration(milliseconds: 1),
      );
      expect(result, 'ok');
      expect(calls, 3);
    });

    test('非瞬时错误立即抛出，不做无谓重试', () async {
      int calls = 0;
      await expectLater(
        NetError.retry<String>(
          () async {
            calls++;
            throw _FakeException('Failed host lookup: nope.invalid');
          },
          attempts: 3,
          baseDelay: const Duration(milliseconds: 1),
        ),
        throwsA(isA<_FakeException>()),
      );
      expect(calls, 1);
    });

    test('shouldRetry 可以否决重试（流式已开始输出时用得上）', () async {
      int calls = 0;
      await expectLater(
        NetError.retry<String>(
          () async {
            calls++;
            throw _FakeException('Software caused connection abort');
          },
          attempts: 5,
          baseDelay: const Duration(milliseconds: 1),
          shouldRetry: (Object _) => false,
        ),
        throwsA(isA<_FakeException>()),
      );
      expect(calls, 1);
    });
  });
}
