import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 一条用户自定义规则：**当 XXX 的时候，就 YYY**。
///
/// 设计上刻意**不做触发器引擎**，而是把规则作为**指令**交给模型。
///
/// 原因是：真正的触发（定时、事件）需要后台常驻执行，
/// 而 Android 会杀后台、还要处理 Doze —— 那是一整套工程，
/// 而且做不到"一定准时"。
///
/// 而"让模型记住这条规则"是**零延迟、零后台、立刻生效**的：
/// 规则进系统提示词，模型每次对话都会看到并遵守。
/// 覆盖了绝大多数真实需求（"回答简短点""问天气先查我的城市"
/// "说'记录'就存笔记"）。
///
/// **诚实地说清边界**：这些规则只在**对话时**生效，
/// 不会在你没打开应用时自己触发。
class CustomRule {
  CustomRule({
    required this.id,
    required this.when_,
    required this.then_,
    this.enabled = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;

  /// "当……的时候"—— 用户可以写得很随意，模型能理解自然语言
  String when_;

  /// "就……"—— 要模型做的事
  String then_;

  bool enabled;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'when': when_,
        'then': then_,
        'enabled': enabled,
        'createdAt': createdAt.toIso8601String(),
      };

  static CustomRule fromJson(Map<String, dynamic> j) => CustomRule(
        id: j['id']?.toString() ?? '',
        when_: j['when']?.toString() ?? '',
        then_: j['then']?.toString() ?? '',
        enabled: j['enabled'] != false,
        createdAt:
            DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// 规则的存储与注入
///
/// 做成单例：规则要在**系统提示词构建时**读到，而那条路径在
/// `AgentRunner` 深处，把它从 main 一路透传下来要改十几个文件。
/// 同项目里 `PythonService` / `TermuxService` 也是这个模式，保持一致。
class RuleStore extends ChangeNotifier {
  RuleStore._(this._file);

  /// 进程内单例。`configure()` 之前 `rules` 为空，所以即使忘了初始化
  /// 也只是"没有规则"，不会崩。
  static late final RuleStore instance;

  static Future<RuleStore> configure(File file) async {
    instance = RuleStore._(file);
    await instance.load();
    return instance;
  }

  final File _file;
  final List<CustomRule> rules = <CustomRule>[];

  Future<void> load() async {
    rules.clear();
    try {
      if (await _file.exists()) {
        final dynamic data = jsonDecode(await _file.readAsString());
        if (data is List) {
          for (final dynamic e in data) {
            rules.add(CustomRule.fromJson(Map<String, dynamic>.from(e as Map)));
          }
        }
      }
    } catch (_) {
      rules.clear();
    }
    notifyListeners();
  }

  Future<void> save() async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(
        jsonEncode(rules.map((CustomRule r) => r.toJson()).toList()),
      );
    } catch (_) {
      // 写失败不致命
    }
  }

  void _changed() {
    notifyListeners();
    save();
  }

  CustomRule add(String when_, String then_) {
    final CustomRule r = CustomRule(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      when_: when_.trim(),
      then_: then_.trim(),
    );
    rules.add(r);
    _changed();
    return r;
  }

  void update(CustomRule r) => _changed();

  void remove(String id) {
    rules.removeWhere((CustomRule r) => r.id == id);
    _changed();
  }

  void toggle(CustomRule r, bool on) {
    r.enabled = on;
    _changed();
  }

  /// 把启用的规则拼成一段注入系统提示词的文本。
  ///
  /// 空列表返回空串 —— 让调用方可以简单地判断"要不要插这段"，
  /// 而不是无条件插一段空标题（那会浪费 token 也干扰模型）。
  ///
  /// **措辞上刻意强调"这是用户明确设定的规则"**：模型对系统提示词里的
  /// 自然语言指令执行力有限，明确标注来源能明显提高遵守率。
  String toPromptSection() {
    final List<CustomRule> on =
        rules.where((CustomRule r) => r.enabled).toList();
    if (on.isEmpty) return '';

    final StringBuffer sb = StringBuffer();
    sb.writeln();
    sb.writeln('用户自定义规则（**由用户本人设定，优先级高于你自己的默认习惯**）：');
    for (final CustomRule r in on) {
      sb.writeln('- 当${r.when_}时，${r.then_}');
    }
    sb.writeln('这些规则在每一轮对话里都生效，不要问用户"要不要遵守"，直接照做。');
    return sb.toString();
  }
}
