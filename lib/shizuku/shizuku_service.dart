import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 一次 shell 执行的结果
class ExecResult {
  const ExecResult({
    required this.code,
    required this.stdout,
    required this.stderr,
    required this.timedOut,
    this.bytes,
  });

  final int code;
  final String stdout;
  final String stderr;
  final bool timedOut;

  /// 二进制输出（截图用）
  final Uint8List? bytes;

  bool get ok => code == 0 && !timedOut;

  /// 优先返回 stdout，为空时退回 stderr —— 很多命令把有用信息写在 stderr
  String get output {
    if (stdout.trim().isNotEmpty) return stdout;
    if (stderr.trim().isNotEmpty) return stderr;
    return '(无输出)';
  }
}

/// Shizuku 通道的 Dart 侧封装。
///
/// 这里**不含任何业务语义**，只负责：状态同步、权限申请、执行命令。
/// 「应用管理 / 文件 / 设置 / 截图」这些概念都在 tools 层用命令组合出来。
class ShizukuService extends ChangeNotifier {
  ShizukuService();

  static const MethodChannel _method = MethodChannel('dsh/shizuku');
  static const EventChannel _event = EventChannel('dsh/shizuku/events');

  bool supported = false;
  bool running = false;
  bool granted = false;

  String? lastError;

  StreamSubscription<dynamic>? _sub;

  /// 三者都满足才能执行命令
  bool get ready => supported && running && granted;

  /// 给 UI 用的一句话状态
  String get statusText {
    if (!supported) return '未连接';
    if (!running) return 'Shizuku 未运行';
    if (!granted) return '未授权';
    return '已连接';
  }

  Future<void> init() async {
    _sub = _event.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object e) {
        lastError = e.toString();
        notifyListeners();
      },
    );
    await refresh();
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final Map<String, dynamic> m = Map<String, dynamic>.from(event);

    switch (m['type']) {
      case 'state':
        supported = m['supported'] == true;
        running = m['running'] == true;
        granted = m['granted'] == true;
        notifyListeners();

      case 'binderReceived':
        running = true;
        notifyListeners();
        unawaited(refresh());

      case 'binderDead':
        running = false;
        granted = false;
        notifyListeners();

      case 'permissionResult':
        granted = m['granted'] == true;
        notifyListeners();
    }
  }

  Future<void> refresh() async {
    try {
      final Map<dynamic, dynamic>? r =
          await _method.invokeMethod<Map<dynamic, dynamic>>('state');
      if (r != null) {
        supported = r['supported'] == true;
        running = r['running'] == true;
        granted = r['granted'] == true;
        lastError = null;
        notifyListeners();
      }
    } on PlatformException catch (e) {
      lastError = e.message;
      notifyListeners();
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
    }
  }

  /// 发起授权请求。结果通过事件通道异步回来，所以这里返回的只是「请求已发出」。
  Future<bool> requestPermission() async {
    try {
      final bool? r = await _method.invokeMethod<bool>('requestPermission');
      return r ?? false;
    } on PlatformException catch (e) {
      lastError = e.message;
      notifyListeners();
      return false;
    }
  }

  /// 以 shell 身份执行命令。
  Future<ExecResult> exec(
    String command, {
    bool binary = false,
    int timeoutMs = 20000,
  }) async {
    if (!ready) {
      return ExecResult(
        code: -2,
        stdout: '',
        stderr: 'Shizuku $statusText，无法执行命令',
        timedOut: false,
      );
    }

    try {
      final Map<dynamic, dynamic>? r =
          await _method.invokeMethod<Map<dynamic, dynamic>>('exec', <String, dynamic>{
        'cmd': command,
        'binary': binary,
        'timeoutMs': timeoutMs,
      });

      if (r == null) {
        return const ExecResult(
            code: -1, stdout: '', stderr: '空返回', timedOut: false);
      }

      final dynamic rawBytes = r['bytes'];

      return ExecResult(
        code: (r['code'] as num?)?.toInt() ?? -1,
        stdout: r['stdout']?.toString() ?? '',
        stderr: r['stderr']?.toString() ?? '',
        timedOut: r['timedOut'] == true,
        bytes: rawBytes is Uint8List ? rawBytes : null,
      );
    } on PlatformException catch (e) {
      return ExecResult(
        code: -1,
        stdout: '',
        stderr: e.message ?? '执行失败',
        timedOut: false,
      );
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
