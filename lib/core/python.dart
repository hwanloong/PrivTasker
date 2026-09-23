import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 一次 Python 执行的结果
class PyResult {
  const PyResult({
    required this.ok,
    this.output = '',
    this.error,
    this.errorType,
  });

  final bool ok;

  /// print 出来的东西（stdout + stderr 合并）
  final String output;

  /// 完整的 traceback。失败时才有。
  final String? error;

  /// 异常类型名（ZeroDivisionError 之类），给模型一个快速判断的抓手
  final String? errorType;

  static PyResult fromJson(String raw) {
    try {
      final Map<String, dynamic> j =
          jsonDecode(raw) as Map<String, dynamic>;
      return PyResult(
        ok: j['ok'] == true,
        output: (j['output'] ?? '').toString(),
        error: j['error']?.toString(),
        errorType: (j['error_type'] ?? j['error'])?.toString(),
      );
    } catch (e) {
      // Python 侧返回了非 JSON —— 说明是更底层的失败（解释器没起来），
      // 把原文带出去，别丢掉线索
      return PyResult(ok: false, error: raw, errorType: 'BadResponse');
    }
  }
}

/// 内嵌 Python 服务。
///
/// **这是 Chaquopy 嵌进来的 CPython，不是 Termux、也不是系统里的 Python。**
/// 用户零配置就有完整的解释器，代价是 APK 大了几十 MB。
class PythonService extends ChangeNotifier {
  PythonService._();

  static final PythonService instance = PythonService._();

  static const MethodChannel _channel = MethodChannel('dsh/python');

  bool _available = false;
  bool get available => _available;

  /// `sys.version`，设置页用来确认解释器真的起来了
  String? _version;
  String? get version => _version;

  /// 最近一次失败原因
  String? _lastError;
  String? get lastError => _lastError;

  /// 已装的第三方包（懒加载）
  List<String>? _packages;
  List<String>? get packages => _packages;

  /// 探测解释器能不能起来。
  ///
  /// **首次调用要启动解释器，可能一两秒**，所以不要在启动路径上 await 它。
  Future<void> refresh() async {
    if (!Platform.isAndroid) {
      _available = false;
      notifyListeners();
      return;
    }
    try {
      final String? raw = await _channel.invokeMethod<String>('info');
      if (raw == null) {
        _available = false;
        _lastError = '通道没有返回';
      } else {
        final Map<String, dynamic> j =
            jsonDecode(raw) as Map<String, dynamic>;
        if (j['version'] != null) {
          _version = j['version'].toString();
          _available = true;
          _lastError = null;
        } else {
          _available = false;
          _lastError = j['error']?.toString() ?? '未知错误';
        }
      }
    } catch (e) {
      _available = false;
      _lastError = '$e';
    }
    notifyListeners();
  }

  Future<List<String>> loadPackages() async {
    if (!Platform.isAndroid) return <String>[];
    try {
      final String? raw = await _channel.invokeMethod<String>('packages');
      if (raw == null) return <String>[];
      final dynamic j = jsonDecode(raw);
      if (j is List) {
        _packages = j.map((dynamic e) => e.toString()).toList();
        notifyListeners();
        return _packages!;
      }
    } catch (_) {
      // 拉不到就拉不到，不影响主流程
    }
    return _packages ?? <String>[];
  }

  /// 执行一段 Python 代码
  Future<PyResult> run(String code, {bool reset = false}) async {
    if (!Platform.isAndroid) {
      return const PyResult(ok: false, error: '当前平台不支持内嵌 Python');
    }
    try {
      final String? raw = await _channel.invokeMethod<String>('run', <String, dynamic>{
        'code': code,
        'reset': reset,
      });
      if (raw == null) {
        return const PyResult(ok: false, error: '通道没有返回结果');
      }
      final PyResult r = PyResult.fromJson(raw);
      // 第一次跑通就认为解释器可用 —— 这比 info() 更有说服力
      if (r.ok && !_available) {
        _available = true;
        notifyListeners();
      }
      return r;
    } catch (e) {
      _lastError = '$e';
      return PyResult(ok: false, error: '调用 Python 失败：$e');
    }
  }
}
