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

  // ------------------------------------------------------ 进度浮窗

  /// 显示底部的"正在干什么"浮窗。
  ///
  /// **只在应用不在前台时调用。** 前台时界面本身就有进度
  /// （工具卡片、转圈），再压一个浮窗是纯视觉噪音。
  /// 所以显示时机由调用方根据生命周期决定，而不是这里判断。
  static Future<void> showActivity(String text) async {
    try {
      await _channel.invokeMethod<bool>(
        'showActivity',
        <String, dynamic>{'text': text},
      );
    } catch (_) {
      // 浮窗是锦上添花，加不上也不该影响 agent 干活
    }
  }

  /// 更新浮窗文案
  static Future<void> updateActivity(String text) async {
    try {
      await _channel.invokeMethod<bool>(
        'updateActivity',
        <String, dynamic>{'text': text},
      );
    } catch (_) {
      // 忽略
    }
  }

  /// 收起浮窗（记住状态，之后还能再显示）
  static Future<void> hideActivity() async {
    try {
      await _channel.invokeMethod<bool>('hideActivity');
    } catch (_) {
      // 忽略
    }
  }

  /// 彻底关掉浮窗（任务结束时用）
  static Future<void> dismissActivity() async {
    try {
      await _channel.invokeMethod<bool>('dismissActivity');
    } catch (_) {
      // 忽略
    }
  }

  /// 把应用拉回前台。
  ///
  /// 用在"agent 干完了"的时候：用户切出去等结果，完成了就把他带回来，
  /// 而不是让他自己想起来切回来看看。
  ///
  /// 后台启动 Activity 在 Android 10+ 受限，但我们同时有前台服务和
  /// 悬浮窗权限，所以是允许的。被系统拦下时静默失败 ——
  /// 还有通知可以点，不该因此报错给用户。
  static Future<bool> bringToFront() async {
    try {
      return await _channel.invokeMethod<bool>('bringToFront') ?? false;
    } catch (_) {
      return false;
    }
  }
}
