import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'ids.dart' as ids;

/// 一条笔记
class Note {
  Note({
    required this.id,
    required this.title,
    this.body = '',
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isMarkdown = false,
    this.folderId,
  })  : tags = tags ?? <String>[],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  String body;
  List<String> tags;
  final DateTime createdAt;
  DateTime updatedAt;

  /// 正文按 Markdown 渲染，还是按纯文本原样显示。
  ///
  /// 存成**每条笔记自己的属性**，而不是全局设置 ——
  /// 记代码片段、贴日志时想要纯文本；写文档、列清单时想要 Markdown。
  /// 这个需求跟着内容走，不跟着应用走。
  bool isMarkdown;

  /// 所属文件夹。**null = 未归类**，在根级显示。
  ///
  /// 刻意允许 null：加文件夹功能时，已经存在的一堆笔记不能被逼着
  /// "塞进某个文件夹" —— 否则用户打开应用会发现东西全跑到了
  /// 一个莫名其妙的地方。**未归类是正常且长期存在的状态，不是过渡态。**
  String? folderId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'body': body,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'isMarkdown': isMarkdown,
        'folderId': folderId,
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
        // 旧数据没有这个字段，默认纯文本 —— 不要默认 Markdown，
        // 否则以前随手记的内容会被当成 Markdown 渲染得乱七八糟
        isMarkdown: j['isMarkdown'] == true,
        // 旧数据没有 folderId → null → 未归类。
        // **绝不给默认文件夹**：那等于替用户搬了一次家。
        folderId: (j['folderId']?.toString().trim().isEmpty ?? true)
            ? null
            : j['folderId'].toString(),
      );
}

/// 一个笔记文件夹
class NoteFolder {
  NoteFolder({
    required this.id,
    required this.name,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
      };

  static NoteFolder fromJson(Map<String, dynamic> j) => NoteFolder(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '未命名',
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
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

  /// 生成 id。委托给 `core/ids.dart` —— 那里解释了**为什么不能只用时间戳**
  /// （Windows 上 `DateTime.now()` 是毫秒级，连续创建会撞 id，而删除按 id
  /// 匹配，一撞就会误删多条）。
  static String newId() => ids.newId();
}

class NoteStore extends _JsonListStore<Note> {
  /// 文件夹存在**另一个文件**里，路径从笔记文件派生。
  ///
  /// 为什么派生而不是多加一个构造参数：那样 main.dart 和测试都要改，
  /// 而它们其实不关心文件夹存在哪。派生路径让调用方一行都不用动。
  // 不能用 super.file：文件夹路径是从笔记文件**派生**的，
  // 初始化列表里需要拿到那个值。
  // ignore: use_super_parameters
  NoteStore(File file)
      : _folderFile = File('${file.parent.path}/note_folders.json'),
        super(file);

  final File _folderFile;

  /// 全部文件夹
  final List<NoteFolder> folders = <NoteFolder>[];

  @override
  Future<void> load() async {
    await super.load();
    folders.clear();
    try {
      if (await _folderFile.exists()) {
        final dynamic data = jsonDecode(await _folderFile.readAsString());
        if (data is List) {
          for (final dynamic e in data) {
            folders.add(NoteFolder.fromJson(Map<String, dynamic>.from(e as Map)));
          }
        }
      }
    } catch (_) {
      folders.clear();
    }
    notifyListeners();
  }

  Future<void> _saveFolders() async {
    try {
      await _folderFile.parent.create(recursive: true);
      await _folderFile.writeAsString(
        jsonEncode(folders.map((NoteFolder f) => f.toJson()).toList()),
      );
    } catch (_) {
      // 写失败不致命
    }
  }

  // ------------------------------------------------------------ 文件夹

  NoteFolder? folderById(String? id) {
    if (id == null) return null;
    for (final NoteFolder f in folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  int countInFolder(String folderId) =>
      items.where((Note n) => n.folderId == folderId).length;

  /// 未归类的笔记数。根级"未归类"那一栏显示它。
  int get unfiledCount =>
      items.where((Note n) => n.folderId == null).length;

  NoteFolder createFolder(String name) {
    final NoteFolder f = NoteFolder(
      id: _JsonListStore.newId(),
      name: name.trim().isEmpty ? '新建文件夹' : name.trim(),
    );
    folders.add(f);
    notifyListeners();
    _saveFolders();
    return f;
  }

  void renameFolder(NoteFolder f, String name) {
    if (name.trim().isEmpty) return;
    f.name = name.trim();
    notifyListeners();
    _saveFolders();
  }

  /// 删文件夹。
  ///
  /// **不删里面的笔记** —— 只是把它们变成"未归类"。
  /// 删文件夹时顺手删掉几十条笔记，是这类功能最容易犯、
  /// 后果也最严重的错误。
  void deleteFolder(String id) {
    folders.removeWhere((NoteFolder f) => f.id == id);
    for (final Note n in items) {
      if (n.folderId == id) n.folderId = null;
    }
    notifyListeners();
    saveQuietly();
    _saveFolders();
  }

  /// 把笔记移到文件夹（[folderId] 为 null 表示移出到"未归类"）
  void moveNote(Note n, String? folderId) {
    n.folderId = folderId;
    n.updatedAt = DateTime.now();
    notifyListeners();
    saveQuietly();
  }

  /// 按文件夹 + 关键词 + 标签筛选。
  ///
  /// 三个条件**叠加**而不是互斥：在某个文件夹里再搜关键词、
  /// 再按标签筛，"找工作时写的那条"才成立。
  ///
  /// [folderId] 传 null 表示"只列未归类的"；传 `'\u0000all'` 表示不按文件夹筛。
  static const String allFolders = '\u0000all';

  List<Note> filter({
    String? folderId,
    String keyword = '',
    String? tag,
  }) {
    Iterable<Note> list = sorted;

    if (folderId != allFolders) {
      list = list.where((Note n) => n.folderId == folderId);
    }

    final String k = keyword.trim().toLowerCase();
    if (k.isNotEmpty) {
      list = list.where((Note n) =>
          n.title.toLowerCase().contains(k) ||
          n.body.toLowerCase().contains(k) ||
          n.tags.any((String t) => t.toLowerCase().contains(k)));
    }

    if (tag != null && tag.trim().isNotEmpty) {
      list = list.where(
          (Note n) => n.tags.any((String t) => t.trim() == tag.trim()));
    }

    return list.toList();
  }

  /// 某个范围（文件夹或全部）内出现过的标签，按出现次数降序。
  /// 标签筛选条要用它 —— 不能列出别的文件夹才有的标签。
  List<String> tagsIn({String? folderId}) {
    final Map<String, int> count = <String, int>{};
    for (final Note n in items) {
      if (folderId != allFolders && n.folderId != folderId) continue;
      for (final String t in n.tags) {
        final String k = t.trim();
        if (k.isEmpty) continue;
        count[k] = (count[k] ?? 0) + 1;
      }
    }
    final List<String> tags = count.keys.toList()
      ..sort((String a, String b) {
        final int c = count[b]!.compareTo(count[a]!);
        return c != 0 ? c : a.compareTo(b);
      });
    return tags;
  }

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
