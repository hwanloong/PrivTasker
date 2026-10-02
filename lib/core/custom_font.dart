import 'dart:io';

import 'package:flutter/services.dart';

/// 用户自己选的字体文件（苹方、思源、任何 `.ttf` / `.otf` / `.ttc`）。
///
/// ## 为什么是"运行时加载"而不是打进 assets
///
/// 苹方（PingFang SC）是苹果的系统字体，**不随仓库分发**，Windows 上也没有。
/// 如果把它写进 `pubspec.yaml` 的 `fonts:` 段会有两个问题：
///
/// 1. **构建会直接失败。** Flutter 不支持"可选字体资源" —— 声明了却找不到
///    文件就是构建错误。于是没有这个字体的人（包括任何克隆仓库的人）
///    连编译都过不去。
/// 2. 字体文件进了仓库就是再分发，那是另一回事。
///
/// 所以改成运行时从文件加载：
///
/// · 字体文件永远不进仓库，没有许可问题
/// · 想换成任何别的字体都不用改代码、不用重新构建
/// · 仓库里没有它，别人照样能构建
///
/// 代价是：字体只对**本机这一份安装**生效，换设备要重新选一次。
/// 那个路径记在 `SharedPreferences` 里，所以同一台设备升级应用不会丢。
///
/// 想要"装一次、每次都有"，就把文件放进 `assets/fonts/` 并写进
/// `pubspec.yaml` 的 `fonts:` 段 —— 见 `assets/fonts/README.md`。
/// 那条路的代价是**每个构建这个仓库的人都要有那个文件**。
class CustomFont {
  CustomFont._();

  /// 注册到引擎时用的家族名。
  ///
  /// 刻意用一个内部固定名字，而不是"文件名"：用户在设置里换字体文件时，
  /// 全项目几十处 `TextStyle` 引用的家族名不用跟着变。
  static const String family = 'UserFont';

  static String? _path;
  static String? _error;

  /// 当前生效的字体文件路径；null = 没加载
  static String? get path => _path;

  /// 上一次加载失败的原因；null = 没失败过
  static String? get error => _error;

  static bool get loaded => _path != null;

  /// 从文件加载并注册。
  ///
  /// 返回 null 表示成功；否则返回一句给用户看的错误说明
  /// （直接显示在设置里，不写日志 —— 用户看不到日志）。
  static Future<String?> loadFrom(String filePath) async {
    _error = null;
    try {
      final File f = File(filePath);
      if (!await f.exists()) {
        _error = '文件不存在：$filePath';
        return _error;
      }

      final Uint8List bytes = await f.readAsBytes();
      if (bytes.length < 4) {
        _error = '文件太小，不像字体';
        return _error;
      }

      // 校验 sfnt 魔数。
      //
      // 这一步是为了挡住最常见的错误：**选错了文件**（选到字体文件夹里的
      // README、选到压缩包、选到桌面快捷方式）。不挡的话 FontLoader 会抛一个
      // 底层异常，用户看到的是"加载失败"却说不出为什么。
      if (!_looksLikeFont(bytes)) {
        _error = '这不像是字体文件（文件头不对）。要选 .ttf / .otf / .ttc';
        return _error;
      }

      final FontLoader loader = FontLoader(family);
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();

      _path = filePath;
      return null;
    } catch (e) {
      // .ttc 是"字体集合"（一个文件装多个字重），Flutter 对它的支持不确定。
      // 这里把原文带出来，用户才知道下一步该干什么（先抽成单字体）。
      _error = '加载失败：$e\n'
          '如果这是 .ttc 集合文件，先用 tools/extract_ttc.dart 抽成单个 .ttf';
      return _error;
    }
  }

  static void clear() {
    _path = null;
    _error = null;
  }

  /// sfnt 魔数：`0x00010000`（TrueType）、`OTTO`（CFF/OpenType）、
  /// `true`、`ttcf`（TrueType 集合，也就是 .ttc）。
  static bool _looksLikeFont(Uint8List b) {
    if (b.length < 4) return false;
    if (b[0] == 0x00 && b[1] == 0x01 && b[2] == 0x00 && b[3] == 0x00) {
      return true;
    }
    final String tag = String.fromCharCodes(<int>[b[0], b[1], b[2], b[3]]);
    return tag == 'OTTO' || tag == 'true' || tag == 'ttcf';
  }

  /// 路径的最后一段，用来在设置里显示"当前用的是哪个文件"。
  static String get fileName {
    final String? p = _path;
    if (p == null) return '';
    return p.split(RegExp(r'[/\\]')).last;
  }
}
