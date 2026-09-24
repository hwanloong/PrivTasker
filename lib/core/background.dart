import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 后台保活状态
class BgStatus {
  const BgStatus({
    this.batteryIgnored = false,
    this.notifEnabled = true,
  });

  /// 是否已加入"电池优化白名单"。
  /// false 时 Doze 会挂起 CPU、断网，长任务跑不完。
  final bool batteryIgnored;

  /// 通知权限（Android 13+）。被拒时前台服务**仍会运行**，只是通知不显示。
  final bool notifEnabled;

  bool get bothOk => batteryIgnored && notifEnabled;
}

/// 后台保活：前台服务 + 电池优化白名单。
///
/// ## 两件事为什么要一起做
///
/// | 机制 | 挡住什么 | 挡不住什么 |
/// |---|---|---|
/// | 前台服务 | **内存回收**（LMK 按优先级杀进程） | Doze 挂起 CPU |
/// | 电池优化白名单 | **Doze**（打盹时挂起 CPU、断网） | —— |
///
/// 只做前者，长任务在息屏后仍会停；只做后者，进程还是可能被回收。
/// **两者互补，缺一不可。**
///
/// ## 但它仍然不是"一定跑完"
///
/// 这是必须说清的边界：国产 ROM 有自己的省电策略（自启动管理、
/// 后台冻结），可能比 Android 原生更激进。做了这两件事**显著提高**
/// 存活率，但不保证。所以 `termux` 工具那边的建议仍然是
/// "长任务写日志文件，之后回来读"，而不是"挂着等它跑完"。
class BackgroundService extends ChangeNotifier {
  BackgroundService._();

  static final BackgroundService instance = BackgroundService._();

  static const MethodChannel _channel = MethodChannel('dsh/bg');

  BgStatus _status = const BgStatus();
  BgStatus get status => _status;

  bool _running = false;

  /// 前台服务当前是否在跑
  bool get running => _running;

  /// 探测状态。设置页进页面时调一次。
  Future<void> refresh() async {
    if (!Platform.isAndroid) return;
    try {
      final bool? b = await _channel.invokeMethod<bool>('batteryIgnored');
      final bool? n = await _channel.invokeMethod<bool>('notifEnabled');
      _status = BgStatus(
        batteryIgnored: b ?? false,
        notifEnabled: n ?? true,
      );
      notifyListeners();
    } catch (_) {
      // 探测失败不影响主流程
    }
  }

  /// 申请忽略电池优化。会跳系统弹窗，用户点"允许"才生效。
  Future<bool> requestBattery() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? ok = await _channel.invokeMethod<bool>('requestBattery');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 开始后台保活，并显示"正在干什么"。
  ///
  /// [text] 会显示在通知里 —— **写具体一点**，
  /// "正在执行任务"这种文案对用户毫无信息量。
  Future<void> start(String text) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('startService', <String, dynamic>{
        'text': text,
      });
      _running = true;
      notifyListeners();
    } catch (_) {
      // 起不来就算了 —— 不能因为保活失败就阻断 agent 干活
    }
  }

  /// 更新通知文案（每轮工具调用都会调）
  Future<void> update(String text) async {
    if (!Platform.isAndroid || !_running) return;
    try {
      await _channel.invokeMethod<void>('updateService', <String, dynamic>{
        'text': text,
      });
    } catch (_) {
      // 忽略
    }
  }

  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopService');
    } catch (_) {
      // 忽略
    }
    _running = false;
    notifyListeners();
  }
}
