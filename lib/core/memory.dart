import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'ids.dart';

/// 一条「记忆」：agent 应该长期记住的、关于用户或环境的事实。
///
/// 和「笔记」的区别：
/// · **笔记**是给**人**看的 —— 有条目、标题、标签、文件夹，用户自己翻。
/// · **记忆**是给**模型**看的 —— 没有标题、没有分类，就是一句句事实，
///   每轮对话都塞进系统提示词。
///
/// 所以这里的字段极简：只有正文和时间。加标题/标签只会让模型写得更犹豫、
/// 让用户更难一眼扫完。
///
/// 和「自定义规则」的区别：规则是**指令**（"当我说记录就存笔记"），
/// 记忆是**事实**（"用户在上海""用户用 DeepSeek"）。两者混在一起模型会分不清
/// 该"照做"还是该"知道"，所以分成两处存、分两段注入。
class MemoryItem {
  MemoryItem({
    required this.id,
    required this.text,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;

  /// 事实本身，一句话。模型写、模型读，所以用自然语言即可。
  String text;

  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
      };

  static MemoryItem fromJson(Map<String, dynamic> j) => MemoryItem(
        id: j['id']?.toString() ?? '',
        text: j['text']?.toString() ?? '',
        createdAt:
            DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// 记忆的存储与注入。
///
/// 做成单例的理由和 `RuleStore` 完全一样：记忆要在**系统提示词构建时**读到，
/// 而那条路径在 `AgentRunner` 深处，从 main 一路透传下来要改十几个文件。
/// 同项目的 `PythonService` / `TermuxService` / `RuleStore` 都是这个模式。
class MemoryStore extends ChangeNotifier {
  MemoryStore._(this._file);

  /// 进程内单例。
  ///
  /// **刻意不用 `static late final`。** 那种写法只能赋值一次，
  /// 第二次 `configure()` 会抛 `LateInitializationError` ——
  /// 生产代码里 `main()` 只调一次所以看不出来，但它带来两个真问题：
  ///
  /// · 这个类**没法测试**：每个用例都要一个干净的实例，只能配置一次就没法做。
  /// · 它是一颗定时炸弹：任何"重新初始化"的代码路径（换账号、清数据后重置）
  ///   一碰就炸，而且报错信息只说"字段已初始化"，看不出是哪里出的问题。
  ///
  /// 可空 + getter 的写法把"没初始化"变成一个**说得清的错误**。
  static MemoryStore? _instance;

  static MemoryStore get instance {
    final MemoryStore? s = _instance;
    if (s == null) {
      throw StateError(
        'MemoryStore 还没初始化。应该在 main() 里调用 MemoryStore.configure()。',
      );
    }
    return s;
  }

  static Future<MemoryStore> configure(File file) async {
    final MemoryStore s = MemoryStore._(file);
    _instance = s;
    await s.load();
    return s;
  }

  final File _file;
  final List<MemoryItem> items = <MemoryItem>[];

  /// 单条记忆的长度上限。
  ///
  /// 记忆是**每轮对话都要注入**的，所以它的成本是"条数 × 长度 × 轮数"。
  /// 不设上限的话，模型很容易写进一整段总结，几十轮下来把上下文吃掉一大块，
  /// 用户只会觉得"越聊越傻"却找不到原因。超了直接截断并告诉模型。
  static const int maxLength = 200;

  /// 条数上限。同上 —— 记忆是常驻成本，必须有个天花板。
  static const int maxItems = 100;

  Future<void> load() async {
    items.clear();
    try {
      if (await _file.exists()) {
        final dynamic data = jsonDecode(await _file.readAsString());
        if (data is List) {
          for (final dynamic e in data) {
            items.add(MemoryItem.fromJson(Map<String, dynamic>.from(e as Map)));
          }
        }
      }
    } catch (_) {
      items.clear();
    }
    notifyListeners();
  }

  Future<void> save() async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(
        jsonEncode(items.map((MemoryItem m) => m.toJson()).toList()),
      );
    } catch (_) {
      // 写失败不致命
    }
  }

  void _changed() {
    notifyListeners();
    save();
  }

  /// 记一条。返回 null 表示成功，否则返回给模型/用户看的失败原因。
  String? add(String text) {
    final String t = text.trim();
    if (t.isEmpty) return '内容为空';
    if (t.length > maxLength) {
      return '太长了（${t.length} 字，上限 $maxLength）。'
          '记忆要短 —— 它是每轮对话都要带上的一句话，不是一篇总结。';
    }
    if (items.length >= maxItems) {
      return '记忆条数已达上限（$maxItems）。先让用户删掉一些不再需要的。';
    }

    // 去重：模型经常反复"记住"同一件事，攒出一堆重复条目，
    // 既浪费上下文又让记忆页没法看。
    for (final MemoryItem m in items) {
      if (m.text == t) return null;
    }

    items.add(MemoryItem(
      id: newId(),
      text: t,
    ));
    _changed();
    return null;
  }

  void remove(String id) {
    items.removeWhere((MemoryItem m) => m.id == id);
    _changed();
  }

  void clear() {
    items.clear();
    _changed();
  }

  /// 按内容片段找。给模型的「忘掉」用 —— 模型手里通常只有那句话，
  /// 没有 id。
  List<MemoryItem> search(String keyword) {
    final String k = keyword.trim().toLowerCase();
    if (k.isEmpty) return <MemoryItem>[];
    return items
        .where((MemoryItem m) => m.text.toLowerCase().contains(k))
        .toList();
  }

  /// 拼成注入系统提示词的一段。
  ///
  /// 返回空串表示"没有记忆"或"用户关掉了" —— 让调用方可以简单判断要不要插，
  /// 而不是无条件插一段空标题（既浪费 token 又干扰模型）。
  ///
  /// **措辞上强调"这是关于用户的既知事实"**：不标注来源的话，模型会把这些
  /// 当成普通上下文，该用的时候想不起来用。这和 `RuleStore.toPromptSection`
  /// 是同一个经验。
  String toPromptSection(bool enabled) {
    if (!enabled || items.isEmpty) return '';

    final StringBuffer sb = StringBuffer();
    sb.writeln();
    sb.writeln('关于用户的既知事实（你自己的长期记忆，不要问用户"你还记得吗"，直接用）：');
    for (final MemoryItem m in items) {
      sb.writeln('- ${m.text}');
    }
    sb.writeln('这些事实可能过时。**如果当前对话里出现了与之冲突的信息，'
        '以当前对话为准**，并考虑更新记忆。');
    return sb.toString();
  }
}
