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
      'list（列出全部）、search（按关键词搜索）、read（读一条的完整内容）、'
      'create（新建）、update（修改）、delete（删除）。'
      '用户说「记一下」「存个笔记」时用 create；'
      '说「我之前记过什么关于 X 的」时用 search。';

  @override
  Map<String, dynamic> get parameters => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'action': <String, dynamic>{
            'type': 'string',
            'enum': <String>['list', 'search', 'read', 'create', 'update', 'delete'],
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
        },
        'required': <String>['action'],
      };

  @override
  RiskAssessment riskFor(Map<String, dynamic> args) {
    if (args.str('action') == 'delete') {
      return RiskAssessment(RiskLevel.caution, <String>['删除笔记，删除后无法恢复']);
    }
    return RiskAssessment.safe;
  }

  @override
  String summarize(Map<String, dynamic> args) {
    final String a = args.str('action');
    if (a == 'create') return '新建笔记：${args.str('title')}';
    if (a == 'search') return '搜索笔记：${args.str('keyword')}';
    if (a == 'list') return '列出笔记';
    return '$a 笔记 ${args.str('id')}';
  }

  @override
  Future<String> run(ToolContext ctx, Map<String, dynamic> args) async {
    final NoteStore store = ctx.notes;
    final String action = args.str('action');

    switch (action) {
      case 'list':
        if (store.items.isEmpty) return '（还没有任何笔记）';
        final StringBuffer sb = StringBuffer('共 ${store.items.length} 条：\n');
        for (final Note n in store.sorted) {
          sb.writeln('- [${n.id}] ${n.title}'
              '${n.tags.isEmpty ? '' : '  #${n.tags.join(' #')}'}'
              '  （更新于 ${_fmt(n.updatedAt)}）');
        }
        return clampOutput(sb.toString());

      case 'search':
        final List<Note> hit = store.search(args.str('keyword'));
        if (hit.isEmpty) return '没有匹配的笔记。';
        final StringBuffer sb = StringBuffer('命中 ${hit.length} 条：\n');
        for (final Note n in hit) {
          sb.writeln('--- [${n.id}] ${n.title}');
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
        return '标题：${n.title}\n'
            '标签：${n.tags.isEmpty ? '无' : n.tags.join('、')}\n'
            '更新：${_fmt(n.updatedAt)}\n\n'
            '${clampOutput(n.body, max: 8000)}';

      case 'create':
        final String title = args.str('title');
        if (title.trim().isEmpty) return '错误：缺少 title';
        final Note n = store.create(
          title: title,
          body: args.str('body'),
          tags: ((args['tags'] as List<dynamic>?) ?? <dynamic>[])
              .map((dynamic e) => e.toString())
              .toList(),
        );
        return '已创建笔记 [${n.id}] ${n.title}';

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
        store.touch(n);
        return '已更新笔记 [${n.id}] ${n.title}';

      case 'delete':
        final Note? n = store.byId(args.str('id'));
        if (n == null) return '找不到 id 为「${args.str('id')}」的笔记。';
        final String t = n.title;
        store.remove(n.id);
        return '已删除笔记「$t」';

      default:
        return '错误：未知 action「$action」';
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
