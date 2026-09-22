import 'package:flutter/services.dart';

/// 系统级悬浮窗确认框的 Dart 侧封装。
///
/// 为什么不用应用内弹窗：工具很容易把别的应用切到前台
/// （`am start`、拉起系统设置页、点开链接……），此时应用内弹窗会被盖住，
/// 用户必须先切回 DSH 才能点确认，体验很别扭，还容易以为程序卡死了。
///
/// 悬浮窗走 `TYPE_APPLICATION_OVERLAY`，由系统合成，无论前台是谁都在最上层。
/// 需要 `SYSTEM_ALERT_WINDOW` 特殊权限（"显示在其他应用上层"），
/// 只能跳系统设置页让用户手动授予。
class OverlayService {
  const OverlayService._();

  static const MethodChannel _channel = MethodChannel('dsh/overlay');

  /// 是否已获得悬浮窗权限
  static Future<bool> canDraw() async {
    try {
      return await _channel.invokeMethod<bool>('canDraw') ?? false;
    } catch (_) {
      // 通道不可用（例如非 Android 平台）时按「没有权限」处理，
      // 调用方会退回应用内弹窗。
      return false;
    }
  }

  /// 跳系统设置页申请权限。用户回来后需要重新调用 [canDraw] 确认。
  static Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod<bool>('requestPermission');
    } catch (_) {
      // 忽略：申请失败最多是继续用应用内弹窗
    }
  }

  /// 弹出悬浮窗确认。返回 true 表示放行。
  ///
  /// 原生侧有 3 分钟无人操作自动拒绝的兜底，不会永远挂着。
  static Future<bool> showConfirm({
    required String title,
    required String command,
    required List<String> reasons,
    required bool dangerous,
  }) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'showConfirm',
        <String, dynamic>{
          'title': title,
          'command': command,
          'reasons': reasons,
          'dangerous': dangerous,
        },
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
