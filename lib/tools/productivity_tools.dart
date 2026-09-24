import '../core/models.dart';
import '../core/productivity.dart';
import 'tool.dart';

/// 解析模型给的时间。
///
/// 模型可能给 ISO 8601，也可能给相对时间（"+2h"、"30m"）。
/// 两种都收，因为让模型每次都算准绝对时间并不现实 ——
/// 它经常不知道自己"现在"是几点，相对时间反而更可靠。
DateTime? parseDueTime(String raw) {
  final String s = raw.trim();
  if (s.isEmpty) return null;

  // 相对时间：+2h / 30m / 3d / 1w
  final RegExpMatch? rel =
      RegExp(r'^\+\s*(\d+)\s*(m|min|h|hr|hour|d|day|w|week)s?$',
              caseSensitive: false)
          .firstMatch(s);
  if (rel != null) {
    final int n = int.tryParse(rel.group(1)!) ?? 0;
    final String unit = rel.group(2)!.toLowerCase();
    final Duration d = switch (unit) {
      'm' || 'min' => Duration(minutes: n),
      'h' || 'hr' || 'hour' => Duration(hours: n),
      'd' || 'day' => Duration(days: n),
      _ => Duration(days: n * 7),
    };
    return DateTime.now().add(d);
  }

  // 绝对时间：ISO 8601
  return DateTime.tryParse(s);
}

String _fmt(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}';
}

/// 相对时间的可读描述
String describeDue(DateTime? due) {
  if (due == null) return '未设定时间';
  final Duration d = due.difference(DateTime.now());
  final String abs = _fmt(due);
  if (d.isNegative) {
    final Duration ago = -d;
    return '$abs（已过期 ${_human(ago)}）';
  }
  return '$abs（还有 ${_human(d)}）';
}

String _human(Duration d) {
  if (d.inDays >= 1) return '${d.inDays} 天';
  if (d.inHours >= 1) return '${d.inHours} 小时';
  if (d.inMinutes >= 1) return '${d.inMinutes} 分钟';
  return '${d.inSeconds} 秒';
}

/// 笔记工具
class NotesTool extends AgentTool {
  const NotesTool();

  @override
  String get name => 'notes';

  @override
  String get title => '笔记';

  @override
  String get description =>
      '读写用户的笔记。action 取值：'
      'list（列出全部，含文件夹结构）、search（按关键词搜索）、'
      'read（读一条的完整内容）、create（新建）、update（修改）、delete（删除）、'
      'folder（新建/重命名/删除文件夹）。\n'
      '用户说「记一下」「存个笔记」时用 create；'
      '说「我之前记过什么关于 X 的」时用 search。\n'
      '**笔记可以放进文件夹**：list 会列出所有文件夹和它们的 id；'
      'create 时给 folder_id 就把新笔记放进那个文件夹，'
      '不给就落在「未归类」。**不要把笔记硬塞进文件夹** —— '
      '未归类是正常状态，只在这条内容确实属于某个已有文件夹时才指定。';

  @override
  Map<String, dynamic> get parameters => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'action': <String, dynamic>{
            'type': 'string',
            'enum': <String>[
              'list',
              'search',
              'read',
              'create',
              'update',
              'delete',
              'folder',
            ],
          },
          'id': <String, dynamic>{
            'type': 'string',
            'description': 'read / update / delete 时的笔记 id（list 结果里能看到）',
          },
          'title': <String, dynamic>{'type': 'string', 'description': '标题'},
          'body': <String, dynamic>{'type': 'string', 'description': '正文内容'},
          'keyword': <String, dynamic>{
            'type': 'string',
            'description': 'search 的关键词',
          },
          'tags': <String, dynamic>{
            'type': 'array',
            'items': <String, dynamic>{'type': 'string'},
            'description': '标签',
          },
          'folder_id': <String, dynamic>{
            'type': 'string',
            'description': 'create / update 时把笔记放进哪个文件夹'
                '（用 list 结果里的文件夹 id）。留空或传 "" 表示移出到「未归类」。',
          },
          'folder_action': <String, dynamic>{
            'type': 'string',
            'enum': <String>['create', 'rename', 'delete'],
            'description': 'action=folder 时的子操作',
          },
          'folder_name': <String, dynamic>{
            'type': 'string',
            'description': 'action=folder 且 folder_action=create/rename 时的文件夹名',
          },
        },
        'required': <String>['action'],
      };

  @override
  RiskAssessment riskFor(Map<String, dynamic> args) {
    final String a = args.str('action');
    if (a == 'delete') {
      return RiskAssessment(RiskLevel.caution, <String>['删除笔记，删除后无法恢复']);
    }
    if (a == 'folder') {
      final String fa = args.str('folder_action');
      if (fa == 'delete') {
        return RiskAssessment(RiskLevel.caution, <String>[
          '删除文件夹。**里面的笔记不会被删除**，它们会变成「未归类」',
        ]);
      }
      return RiskAssessment(
        RiskLevel.caution,
        <String>['${fa == 'rename' ? '重命名' : '新建'}文件夹：${args.str('folder_name')}'],
      );
    }
    return RiskAssessment.safe;
  }

  @override
  String summarize(Map<String, dynamic> args) {
    final String a = args.str('action');
    if (a == 'create') {
      final String f = args.str('folder_id');
      return '新建笔记：${args.str('title')}${f.isEmpty ? '' : '（放进文件夹 $f）'}';
    }
    if (a == 'search') return '搜索笔记：${args.str('keyword')}';
    if (a == 'list') return '列出笔记';
    if (a == 'folder') {
      return '${args.str('folder_action')} 文件夹 ${args.str('folder_name')}';
    }
    return '$a 笔记 ${args.str('id')}';
  }

  @override
  Future<String> run(ToolContext ctx, Map<String, dynamic> args) async {
    final NoteStore store = ctx.notes;
    final String action = args.str('action');

    switch (action) {
      case 'list':
        if (store.items.isEmpty) return '（还没有任何笔记）';
        final StringBuffer sb = StringBuffer();

        // 先列文件夹 —— 模型需要知道 id 才能把笔记放进去
        if (store.folders.isNotEmpty) {
          sb.writeln('文件夹（${store.folders.length} 个）：');
          for (final NoteFolder f in store.folders) {
            sb.writeln('- [${f.id}] ${f.name}'
                '（${store.countInFolder(f.id)} 条）');
          }
          sb.writeln();
        }
        sb.writeln('未归类 ${store.unfiledCount} 条：');
        // 只列未归类的 —— 归了类的在上面文件夹那栏，重复列会让模型
        // 以为有两条不同的笔记
        final List<Note> unfiled =
            store.items.where((Note n) => n.folderId == null).toList();
        if (unfiled.isEmpty) {
          sb.writeln('（没有）');
        } else {
          for (final Note n in unfiled) {
            sb.writeln('- [${n.id}] ${n.title}'
                '${n.tags.isEmpty ? '' : '  #${n.tags.join(' #')}'}'
                '  （更新于 ${_fmt(n.updatedAt)}）');
          }
        }
        return clampOutput(sb.toString());

      case 'search':
        // 搜索**跨文件夹** —— 用户问"我之前记过什么关于 X 的"，
        // 不会希望因为那条在某个文件夹里就搜不到
        final List<Note> hit = store.search(args.str('keyword'));
        if (hit.isEmpty) return '没有匹配的笔记。';
        final StringBuffer sb = StringBuffer('命中 ${hit.length} 条：\n');
        for (final Note n in hit) {
          final NoteFolder? f = store.folderById(n.folderId);
          sb.writeln('--- [${n.id}] ${n.title}'
              '${f == null ? '' : '  📁${f.name}'}');
          // 带一段正文摘要，模型往往不用再读一次全文
          final String body = n.body.trim();
          if (body.isNotEmpty) {
            sb.writeln(body.length > 400 ? '${body.substring(0, 400)}…' : body);
          }
        }
        return clampOutput(sb.toString());

      case 'read':
        final Note? n = store.byId(args.str('id'));
        if (n == null) return '找不到 id 为「${args.str('id')}」的笔记。';
        final NoteFolder? f = store.folderById(n.folderId);
        return '标题：${n.title}\n'
            '文件夹：${f?.name ?? '未归类'}\n'
            '标签：${n.tags.isEmpty ? '无' : n.tags.join('、')}\n'
            '更新：${_fmt(n.updatedAt)}\n\n'
            '${clampOutput(n.body, max: 8000)}';

      case 'create':
        final String title = args.str('title');
        if (title.trim().isEmpty) return '错误：缺少 title';

        // 指定的文件夹必须真的存在 —— 否则会创建一个指向不存在文件夹的笔记，
        // 那条笔记在界面上永远不会出现在任何地方（既不在文件夹里，
        // 也不在"未归类"里），等于凭空消失
        final String wanted = args.str('folder_id').trim();
        String? folderId;
        if (wanted.isNotEmpty) {
          if (store.folderById(wanted) == null) {
            return '错误：找不到文件夹「$wanted」。'
                '请先用 action=list 看现有文件夹，或省略 folder_id 让它落在「未归类」。';
          }
          folderId = wanted;
        }

        final Note n = store.create(
          title: title,
          body: args.str('body'),
          tags: ((args['tags'] as List<dynamic>?) ?? <dynamic>[])
              .map((dynamic e) => e.toString())
              .toList(),
        )..folderId = folderId;
        store.saveQuietly();

        final NoteFolder? nf = store.folderById(folderId);
        return '已创建笔记 [${n.id}] ${n.title}'
            '（位置：${nf?.name ?? '未归类'}）';

      case 'update':
        final Note? n = store.byId(args.str('id'));
        if (n == null) return '找不到 id 为「${args.str('id')}」的笔记。';
        if (args.containsKey('title')) n.title = args.str('title');
        if (args.containsKey('body')) n.body = args.str('body');
        if (args.containsKey('tags')) {
          n.tags = ((args['tags'] as List<dynamic>?) ?? <dynamic>[])
              .map((dynamic e) => e.toString())
              .toList();
        }
        // folder_id 传空串 = 移出到未归类；不传 = 不动
        if (args.containsKey('folder_id')) {
          final String w = args.str('folder_id').trim();
          if (w.isEmpty) {
            n.folderId = null;
          } else if (store.folderById(w) == null) {
            return '错误：找不到文件夹「$w」，笔记的文件夹没有改动。';
          } else {
            n.folderId = w;
          }
        }
        store.touch(n);
        final NoteFolder? uf = store.folderById(n.folderId);
        return '已更新笔记 [${n.id}] ${n.title}'
            '（位置：${uf?.name ?? '未归类'}）';

      case 'delete':
        final Note? n = store.byId(args.str('id'));
        if (n == null) return '找不到 id 为「${args.str('id')}」的笔记。';
        final String t = n.title;
        store.remove(n.id);
        return '已删除笔记「$t」';

      case 'folder':
        return _folderAction(store, args);

      default:
        return '错误：未知 action「$action」';
    }
  }

  /// 文件夹的增删改
  String _folderAction(NoteStore store, Map<String, dynamic> args) {
    final String fa = args.str('folder_action').trim();
    final String name = args.str('folder_name').trim();
    final String id = args.str('id').trim();

    switch (fa) {
      case 'create':
        if (name.isEmpty) return '错误：缺少 folder_name';
        final NoteFolder f = store.createFolder(name);
        return '已创建文件夹 [${f.id}] ${f.name}';

      case 'rename':
        final NoteFolder? f = store.folderById(id);
        if (f == null) return '找不到 id 为「$id」的文件夹。';
        if (name.isEmpty) return '错误：缺少 folder_name';
        store.renameFolder(f, name);
        return '已重命名文件夹为「$name」';

      case 'delete':
        final NoteFolder? f = store.folderById(id);
        if (f == null) return '找不到 id 为「$id」的文件夹。';
        final int n = store.countInFolder(id);
        final String fname = f.name;
        store.deleteFolder(id);
        // 明确说明笔记没被删 —— 模型需要知道，用户更需要知道
        return '已删除文件夹「$fname」。'
            '里面的 $n 条笔记**没有被删除**，它们变成了「未归类」。';

      default:
        return '错误：folder_action 取值应为 create / rename / delete';
    }
  }
}

/// 任务工具
class TasksTool extends AgentTool {
  const TasksTool();

  @override
  String get name => 'tasks';

  @override
  String get title => '任务';

  @override
  String get description =>
      '读写用户的任务清单（带执行时间）。action 取值：'
      'list（列出，可只看未完成）、create（新建）、update（改标题/详情/时间）、'
      'complete（标记完成）、reopen（重新打开）、delete（删除）。'
      'due_at 支持 ISO 8601（2026-09-25T18:00）或相对时间（+2h / 30m / 3d）。'
      '用户说「提醒我」「明天要做什么」时用它。';

  @override
  Map<String, dynamic> get parameters => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'action': <String, dynamic>{
            'type': 'string',
            'enum': <String>[
              'list',
              'create',
              'update',
              'complete',
              'reopen',
              'delete',
            ],
          },
          'id': <String, dynamic>{
            'type': 'string',
            'description': 'update / complete / reopen / delete 时的任务 id',
          },
          'title': <String, dynamic>{'type': 'string', 'description': '任务标题'},
          'detail': <String, dynamic>{'type': 'string', 'description': '补充说明'},
          'due_at': <String, dynamic>{
            'type': 'string',
            'description': '执行时间。ISO 8601 或相对时间（如 +2h、30m、3d）',
          },
          'pending_only': <String, dynamic>{
            'type': 'boolean',
            'description': 'list 时是否只列未完成的，默认 true',
          },
        },
        'required': <String>['action'],
      };

  @override
  RiskAssessment riskFor(Map<String, dynamic> args) {
    if (args.str('action') == 'delete') {
      return RiskAssessment(RiskLevel.caution, <String>['删除任务，删除后无法恢复']);
    }
    return RiskAssessment.safe;
  }

  @override
  String summarize(Map<String, dynamic> args) {
    final String a = args.str('action');
    if (a == 'create') {
      final String due = args.str('due_at');
      return '新建任务：${args.str('title')}${due.isEmpty ? '' : '（$due）'}';
    }
    if (a == 'list') return '列出任务';
    if (a == 'complete') return '完成任务 ${args.str('id')}';
    return '$a 任务 ${args.str('id')}';
  }

  @override
  Future<String> run(ToolContext ctx, Map<String, dynamic> args) async {
    final TaskStore store = ctx.tasks;
    final String action = args.str('action');

    switch (action) {
      case 'list':
        final bool pendingOnly = args.boolVal('pending_only', fallback: true);
        final List<TaskItem> list =
            pendingOnly ? store.pending : store.sorted;
        if (list.isEmpty) {
          return pendingOnly ? '（没有未完成的任务）' : '（还没有任何任务）';
        }

        final StringBuffer sb = StringBuffer();
        final List<TaskItem> over = store.overdue;
        if (over.isNotEmpty) {
          sb.writeln('⚠ 已过期 ${over.length} 条');
        }
        sb.writeln('共 ${list.length} 条：\n');
        for (final TaskItem t in list) {
          sb.writeln('- [${t.id}] ${t.done ? '✓' : '○'} ${t.title}');
          sb.writeln('    执行时间：${describeDue(t.dueAt)}');
          if (t.detail.trim().isNotEmpty) {
            sb.writeln('    说明：${t.detail.trim()}');
          }
        }
        // 顺带把「现在几点」告诉模型 —— 它常常算不准相对时间
        sb.writeln('\n（当前时间：${_fmt(DateTime.now())}）');
        return clampOutput(sb.toString());

      case 'create':
        final String title = args.str('title');
        if (title.trim().isEmpty) return '错误：缺少 title';

        final String rawDue = args.str('due_at').trim();
        DateTime? due;
        if (rawDue.isNotEmpty) {
          due = parseDueTime(rawDue);
          if (due == null) {
            return '错误：无法解析执行时间「$rawDue」。'
                '请用 ISO 8601（2026-09-25T18:00）或相对时间（+2h / 30m / 3d）。';
          }
        }

        final TaskItem t = store.create(
          title: title,
          detail: args.str('detail'),
          dueAt: due,
        );
        return '已创建任务 [${t.id}] ${t.title}\n'
            '执行时间：${describeDue(t.dueAt)}\n'
            '（当前时间：${_fmt(DateTime.now())}）';

      case 'update':
        final TaskItem? t = store.byId(args.str('id'));
        if (t == null) return '找不到 id 为「${args.str('id')}」的任务。';
        if (args.containsKey('title')) t.title = args.str('title');
        if (args.containsKey('detail')) t.detail = args.str('detail');
        if (args.containsKey('due_at')) {
          final String raw = args.str('due_at').trim();
          if (raw.isEmpty) {
            t.dueAt = null;
          } else {
            final DateTime? d = parseDueTime(raw);
            if (d == null) return '错误：无法解析执行时间「$raw」';
            t.dueAt = d;
          }
        }
        store.update(t);
        return '已更新任务 [${t.id}] ${t.title}\n'
            '执行时间：${describeDue(t.dueAt)}';

      case 'complete':
        final TaskItem? t = store.byId(args.str('id'));
        if (t == null) return '找不到 id 为「${args.str('id')}」的任务。';
        store.setDone(t, true);
        return '已完成任务「${t.title}」';

      case 'reopen':
        final TaskItem? t = store.byId(args.str('id'));
        if (t == null) return '找不到 id 为「${args.str('id')}」的任务。';
        store.setDone(t, false);
        return '已重新打开任务「${t.title}」';

      case 'delete':
        final TaskItem? t = store.byId(args.str('id'));
        if (t == null) return '找不到 id 为「${args.str('id')}」的任务。';
        final String title = t.title;
        store.remove(t.id);
        return '已删除任务「$title」';

      default:
        return '错误：未知 action「$action」';
    }
  }
}
