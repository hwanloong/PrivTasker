import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 一次 Termux 命令的结果
class TermuxResult {
  const TermuxResult({
    required this.ok,
    this.stdout = '',
    this.stderr = '',
    this.exitCode = -1,
    this.error,
    this.errorKind,
    this.background = false,
  });

  final bool ok;
  final String stdout;
  final String stderr;
  final int exitCode;
  final String? error;
  final String? errorKind;
  final bool background;

  /// 合并输出，给模型看的
  String get combined {
    final StringBuffer sb = StringBuffer();
    if (stdout.trim().isNotEmpty) sb.write(stdout.trim());
    if (stderr.trim().isNotEmpty) {
      if (sb.isNotEmpty) sb.write('\n');
      sb.write('[stderr]\n${stderr.trim()}');
    }
    if (sb.isEmpty) sb.write('（无输出）');
    return sb.toString();
  }
}

/// Termux 可用性状态
enum TermuxStatus {
  /// 没装 Termux
  notInstalled,

  /// 装了，但我们没有 RUN_COMMAND 权限（理论上不会发生，manifest 里已声明）
  noPermission,

  /// 装了也有权限，但还没实际跑通过
  ///
  /// **这个状态是必要的**：`allow-external-apps` 无法用代码查询，
  /// 只能靠第一次真实调用是否成功来判定。所以"看起来可用"和
  /// "真的能跑"之间必须区分，否则出错时不知道该怪谁。
  notVerified,

  /// 已经成功执行过至少一条命令
  ready,

  /// 平台不支持（非 Android，比如 golden 测试环境）
  unsupported,
}

/// Termux 连接服务
class TermuxService extends ChangeNotifier {
  TermuxService._();

  static final TermuxService instance = TermuxService._();

  static const MethodChannel _channel = MethodChannel('dsh/termux');

  TermuxStatus _status = TermuxStatus.unsupported;
  TermuxStatus get status => _status;

  /// 最近一次失败的原因，设置页用来给用户看
  String? _lastError;
  String? get lastError => _lastError;

  bool get isReady => _status == TermuxStatus.ready;

  /// 能不能尝试执行 —— notVerified 也放行，因为只有试了才知道
  bool get canAttempt =>
      _status == TermuxStatus.ready || _status == TermuxStatus.notVerified;

  String get statusLabel => switch (_status) {
        TermuxStatus.notInstalled => '未安装 Termux',
        TermuxStatus.noPermission => '缺少 RUN_COMMAND 权限',
        TermuxStatus.notVerified => '已安装（尚未验证）',
        TermuxStatus.ready => '可用',
        TermuxStatus.unsupported => '当前平台不支持',
      };

  /// 启动时探测一次
  Future<void> refresh() async {
    if (!Platform.isAndroid) {
      _status = TermuxStatus.unsupported;
      notifyListeners();
      return;
    }
    try {
      final dynamic r = await _channel.invokeMethod<dynamic>('status');
      final Map<dynamic, dynamic> m =
          r is Map ? r : <dynamic, dynamic>{};
      final bool installed = m['installed'] == true;
      final bool permitted = m['permitted'] == true;

      if (!installed) {
        _status = TermuxStatus.notInstalled;
      } else if (!permitted) {
        _status = TermuxStatus.noPermission;
      } else if (_status != TermuxStatus.ready) {
        // 已经成功跑过就别退回去
        _status = TermuxStatus.notVerified;
      }
      _lastError = null;
    } catch (e) {
      _status = TermuxStatus.unsupported;
      _lastError = '$e';
    }
    notifyListeners();
  }

  /// 执行一条命令
  Future<TermuxResult> run(
    String command, {
    String? workdir,
    bool background = false,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (!Platform.isAndroid) {
      return const TermuxResult(ok: false, error: '当前平台不支持 Termux');
    }

    try {
      final dynamic raw = await _channel.invokeMethod<dynamic>('run', <String, dynamic>{
        'command': command,
        'workdir': workdir,
        'background': background,
        'timeoutMs': timeout.inMilliseconds,
      });

      final Map<dynamic, dynamic> m =
          raw is Map ? raw : <dynamic, dynamic>{};

      final TermuxResult result = TermuxResult(
        ok: m['ok'] == true,
        stdout: (m['stdout'] ?? '').toString(),
        stderr: (m['stderr'] ?? '').toString(),
        exitCode: (m['exitCode'] as num?)?.toInt() ?? -1,
        error: m['error']?.toString(),
        errorKind: m['errorKind']?.toString(),
        background: m['background'] == true,
      );

      if (result.ok) {
        // 第一次成功执行 —— 说明 allow-external-apps 是开着的
        if (_status != TermuxStatus.ready) {
          _status = TermuxStatus.ready;
          notifyListeners();
        }
      } else {
        _lastError = result.error;
        // NO_RESULT 基本就是 allow-external-apps 没开
        if (result.errorKind == 'NOT_INSTALLED') {
          _status = TermuxStatus.notInstalled;
          notifyListeners();
        }
      }

      return result;
    } catch (e) {
      _lastError = '$e';
      return TermuxResult(ok: false, error: '调用 Termux 失败：$e');
    }
  }
}
