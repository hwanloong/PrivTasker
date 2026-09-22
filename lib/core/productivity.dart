import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 一条笔记
class Note {
  Note({
    required this.id,
    required this.title,
    this.body = '',
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : tags = tags ?? <String>[],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  String body;
  List<String> tags;
  final DateTime createdAt;
  DateTime updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'body': body,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static Note fromJson(Map<String, dynamic> j) => Note(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        body: j['body']?.toString() ?? '',
        tags: ((j['tags'] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList(),
        createdAt:
            DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
        updatedAt:
            DateTime.tryParse(j['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// 一条任务
class TaskItem {
  TaskItem({
    required this.id,
    required this.title,
    this.detail = '',
    this.dueAt,
    this.done = false,
    DateTime? createdAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  String title;
  String detail;

  /// 计划执行时间。为空表示「没有时间要求」。
  DateTime? dueAt;

  bool done;
  final DateTime createdAt;
  DateTime? completedAt;

  bool get overdue =>
      !done && dueAt != null && dueAt!.isBefore(DateTime.now());

  /// 距执行时间还有多久（负数表示已过期）。没有时间要求时返回 null。
  Duration? get remaining => dueAt?.difference(DateTime.now());

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'detail': detail,
        'dueAt': dueAt?.toIso8601String(),
        'done': done,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
      };

  static TaskItem fromJson(Map<String, dynamic> j) => TaskItem(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        detail: j['detail']?.toString() ?? '',
        dueAt: DateTime.tryParse(j['dueAt']?.toString() ?? ''),
        done: j['done'] == true,
        createdAt:
            DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
        completedAt: DateTime.tryParse(j['completedAt']?.toString() ?? ''),
      );
}

/// 通用 JSON 列表存储。
///
/// 笔记和任务的存储需求完全一样（一个 JSON 文件 + 列表 + 增删改 + 通知），
/// 所以抽成基类，避免两份几乎一样的代码各自长 bug。
abstract class _JsonListStore<T> extends ChangeNotifier {
  _JsonListStore(this._file);

  final File _file;
  final List<T> items = <T>[];

  T fromJson(Map<String, dynamic> j);
  Map<String, dynamic> toJson(T item);
  String idOf(T item);

  Future<void> load() async {
    items.clear();
    try {
      if (await _file.exists()) {
        final dynamic data = jsonDecode(await _file.readAsString());
        if (data is List) {
          for (final dynamic e in data) {
            items.add(fromJson(Map<String, dynamic>.from(e as Map)));
          }
        }
      }
    } catch (_) {
      // 文件损坏时不该阻止 app 启动，当空列表处理
      items.clear();
    }
    notifyListeners();
  }

  Future<void> save() async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(
        jsonEncode(items.map(toJson).toList()),
      );
    } catch (_) {
      // 写失败不致命
    }
  }

  void saveQuietly() => save();

  T? byId(String id) {
    for (final T e in items) {
      if (idOf(e) == id) return e;
    }
    return null;
  }

  void remove(String id) {
    items.removeWhere((T e) => idOf(e) == id);
    notifyListeners();
    saveQuietly();
  }

  void replaceAll(List<T> next) {
    items
      ..clear()
      ..addAll(next);
    notifyListeners();
    saveQuietly();
  }

  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toString();
}

class NoteStore extends _JsonListStore<Note> {
  NoteStore(super.file);

  @override
  Note fromJson(Map<String, dynamic> j) => Note.fromJson(j);

  @override
  Map<String, dynamic> toJson(Note item) => item.toJson();

  @override
  String idOf(Note item) => item.id;

  /// 最近更新的排前面
  List<Note> get sorted {
    final List<Note> list = List<Note>.from(items)
      ..sort((Note a, Note b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Note create({String title = '', String body = '', List<String>? tags}) {
    final Note n = Note(
      id: _JsonListStore.newId(),
      title: title.trim().isEmpty ? '新笔记' : title.trim(),
      body: body,
      tags: tags,
    );
    items.add(n);
    notifyListeners();
    saveQuietly();
    return n;
  }

  void touch(Note n) {
    n.updatedAt = DateTime.now();
    notifyListeners();
    saveQuietly();
  }

  /// 按关键词搜索标题和正文
  List<Note> search(String keyword) {
    final String k = keyword.trim().toLowerCase();
    if (k.isEmpty) return sorted;
    return sorted
        .where((Note n) =>
            n.title.toLowerCase().contains(k) ||
            n.body.toLowerCase().contains(k) ||
            n.tags.any((String t) => t.toLowerCase().contains(k)))
        .toList();
  }
}

class TaskStore extends _JsonListStore<TaskItem> {
  TaskStore(super.file);

  @override
  TaskItem fromJson(Map<String, dynamic> j) => TaskItem.fromJson(j);

  @override
  Map<String, dynamic> toJson(TaskItem item) => item.toJson();

  @override
  String idOf(TaskItem item) => item.id;

  /// 未完成在前；同组内按执行时间排，没有时间的排最后。
  List<TaskItem> get sorted {
    final List<TaskItem> list = List<TaskItem>.from(items);
    list.sort((TaskItem a, TaskItem b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      if (a.dueAt == null && b.dueAt == null) {
        return b.createdAt.compareTo(a.createdAt);
      }
      if (a.dueAt == null) return 1;
      if (b.dueAt == null) return -1;
      return a.dueAt!.compareTo(b.dueAt!);
    });
    return list;
  }

  List<TaskItem> get pending => sorted.where((TaskItem t) => !t.done).toList();

  /// 已过期且未完成
  List<TaskItem> get overdue => pending.where((TaskItem t) => t.overdue).toList();

  /// 今天之内到期的
  List<TaskItem> get dueToday {
    final DateTime now = DateTime.now();
    final DateTime end = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    return pending
        .where((TaskItem t) =>
            t.dueAt != null &&
            !t.dueAt!.isBefore(now) &&
            t.dueAt!.isBefore(end))
        .toList();
  }

  TaskItem create({
    required String title,
    String detail = '',
    DateTime? dueAt,
  }) {
    final TaskItem t = TaskItem(
      id: _JsonListStore.newId(),
      title: title.trim().isEmpty ? '新任务' : title.trim(),
      detail: detail,
      dueAt: dueAt,
    );
    items.add(t);
    notifyListeners();
    saveQuietly();
    return t;
  }

  void setDone(TaskItem t, bool done) {
    t.done = done;
    t.completedAt = done ? DateTime.now() : null;
    notifyListeners();
    saveQuietly();
  }

  void toggle(TaskItem t) => setDone(t, !t.done);

  void update(TaskItem t) {
    notifyListeners();
    saveQuietly();
  }
}
