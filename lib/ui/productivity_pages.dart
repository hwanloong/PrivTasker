import 'package:flutter/material.dart';

import '../core/productivity.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'home_shell.dart';

String _two(int v) => v.toString().padLeft(2, '0');

String fmtDateTime(DateTime d) =>
    '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

// ============================================================ 笔记

class NotesPage extends StatefulWidget {
  const NotesPage({super.key, required this.store});

  final NoteStore store;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final TextEditingController _search = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onChange);
    _search.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);
    final List<Note> list = widget.store.search(_search.text);

    return Scaffold(
      backgroundColor:
          s == AppSurface.dark ? AppColors.darkBg : AppColors.lightBg,
      body: Column(
        children: <Widget>[
          AppHeader(
            title: '笔记',
            subtitle: widget.store.items.isEmpty
                ? '还没有笔记'
                : '共 ${widget.store.items.length} 条',
            actions: <Widget>[
              GlassIconButton(
                icon: _searching ? Icons.close_rounded : Icons.search_rounded,
                tooltip: '搜索',
                size: 36,
                iconSize: 18,
                onTap: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) _search.clear();
                }),
              ),
              const SizedBox(width: 6),
              GlassIconButton(
                icon: Icons.add_rounded,
                tooltip: '新建笔记',
                size: 36,
                iconSize: 18,
                onTap: () => _edit(null),
              ),
            ],
            bottom: _searching
                ? Container(
                    decoration: BoxDecoration(
                      color: s.surface,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: s.border, width: 0.9),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    child: TextField(
                      controller: _search,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      style: AppFonts.body(size: 14.5, color: s.text),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 11),
                        hintText: '搜索标题、正文或标签',
                        hintStyle: AppFonts.body(size: 14, color: s.muted),
                      ),
                    ),
                  )
                : null,
          ),
          Expanded(
            child: list.isEmpty
                ? EmptyHint(
                    icon: Icons.sticky_note_2_outlined,
                    title: _search.text.trim().isEmpty ? '还没有笔记' : '没有匹配的笔记',
                    desc: _search.text.trim().isEmpty
                        ? '点右上角「+」新建。\n也可以直接对 Agent 说「记一下……」，它会替你写进来。'
                        : '换个关键词试试。',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    itemCount: list.length,
                    itemBuilder: (BuildContext c, int i) => _tile(s, list[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tile(AppSurface s, Note n) {
    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: () => _edit(n),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  n.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.body(
                    size: 15,
                    weight: FontWeight.w600,
                    color: s.text,
                    height: 1.35,
                  ),
                ),
              ),
              if (n.tags.isNotEmpty)
                GlassChip(label: n.tags.first, dense: true, color: AppColors.accent),
            ],
          ),
          if (n.body.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              n.body.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.body(size: 13, color: s.muted, height: 1.5),
            ),
          ],
          const SizedBox(height: 7),
          Text(
            fmtDateTime(n.updatedAt),
            style: AppFonts.code(size: 10.5, color: s.muted),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(Note? existing) async {
    final TextEditingController title =
        TextEditingController(text: existing?.title ?? '');
    final TextEditingController body =
        TextEditingController(text: existing?.body ?? '');
    final TextEditingController tags =
        TextEditingController(text: existing?.tags.join(' ') ?? '');
    final AppSurface s = AppSurface.of(context);

    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          decoration: BoxDecoration(
            color:
                s == AppSurface.dark ? AppColors.darkBg : AppColors.lightBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: s.border, width: 0.8)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      existing == null ? '新建笔记' : '编辑笔记',
                      style: AppFonts.body(
                        size: 17,
                        weight: FontWeight.w700,
                        color: s.text,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (existing != null)
                    GlassIconButton(
                      icon: Icons.delete_outline_rounded,
                      tooltip: '删除',
                      size: 34,
                      iconSize: 17,
                      color: AppColors.danger,
                      onTap: () {
                        widget.store.remove(existing.id);
                        Navigator.of(ctx).pop(false);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  children: <Widget>[
                    _sheetInput(s, title, '标题', size: 16),
                    const SizedBox(height: 9),
                    _sheetInput(s, body, '正文', maxLines: 10),
                    const SizedBox(height: 9),
                    _sheetInput(s, tags, '标签（空格分隔）', mono: true),
                    const SizedBox(height: 16),
                    GlassButton(
                      label: '保存',
                      accent: true,
                      expand: true,
                      onTap: () => Navigator.of(ctx).pop(true),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved == true) {
      final List<String> tagList = tags.text
          .split(RegExp(r'\s+'))
          .where((String t) => t.trim().isNotEmpty)
          .toList();
      if (existing == null) {
        widget.store.create(
          title: title.text,
          body: body.text,
          tags: tagList,
        );
      } else {
        existing.title =
            title.text.trim().isEmpty ? existing.title : title.text.trim();
        existing.body = body.text;
        existing.tags = tagList;
        widget.store.touch(existing);
      }
    }

    title.dispose();
    body.dispose();
    tags.dispose();
  }
}

/// 表单输入框（笔记和任务的编辑弹窗共用）。
///
/// 放在顶层而不是某个 State 里：两个页面都要用，
/// 挂在 NotesPage 上会让 TasksPage 依赖一个跟它无关的类，
/// 而且那种 `NotesPage._input` 的写法一旦有人重命名就会连带崩掉。
Widget _sheetInput(
  AppSurface s,
  TextEditingController c,
  String hint, {
  int maxLines = 1,
  double size = 14.5,
  bool mono = false,
}) {
  return Container(
    decoration: BoxDecoration(
      color: s.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: s.border, width: 0.9),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: TextField(
      controller: c,
      maxLines: maxLines,
      style: mono
          ? AppFonts.code(size: size, color: s.text)
          : AppFonts.body(size: size, color: s.text, height: 1.5),
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 11),
        hintText: hint,
        hintStyle: AppFonts.body(size: size - 1, color: s.muted),
      ),
    ),
  );
}

// ============================================================ 任务

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, required this.store});

  final TaskStore store;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  bool _showDone = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);
    final List<TaskItem> pending = widget.store.pending;
    final List<TaskItem> done = widget.store.items
        .where((TaskItem t) => t.done)
        .toList()
      ..sort((TaskItem a, TaskItem b) =>
          (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt));

    return Scaffold(
      backgroundColor:
          s == AppSurface.dark ? AppColors.darkBg : AppColors.lightBg,
      body: Column(
        children: <Widget>[
          AppHeader(
            title: '任务',
            subtitle: _subtitle(pending),
            actions: <Widget>[
              GlassIconButton(
                icon: _showDone
                    ? Icons.visibility_off_outlined
                    : Icons.history_rounded,
                tooltip: _showDone ? '隐藏已完成' : '显示已完成',
                size: 36,
                iconSize: 18,
                onTap: () => setState(() => _showDone = !_showDone),
              ),
              const SizedBox(width: 6),
              GlassIconButton(
                icon: Icons.add_rounded,
                tooltip: '新建任务',
                size: 36,
                iconSize: 18,
                onTap: () => _edit(null),
              ),
            ],
          ),
          Expanded(
            child: pending.isEmpty && (!_showDone || done.isEmpty)
                ? EmptyHint(
                    icon: Icons.check_circle_outline_rounded,
                    title: '没有待办任务',
                    desc: '点右上角「+」新建，并设定执行时间。\n'
                        '也可以直接对 Agent 说「提醒我明天下午三点交报告」。',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    children: <Widget>[
                      if (pending.isNotEmpty) ...<Widget>[
                        _sectionLabel(s, '待办 ${pending.length}'),
                        ...pending.map((TaskItem t) => _tile(s, t)),
                      ],
                      if (_showDone && done.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 14),
                        _sectionLabel(s, '已完成 ${done.length}'),
                        ...done.map((TaskItem t) => _tile(s, t)),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _subtitle(List<TaskItem> pending) {
    final int over = widget.store.overdue.length;
    final int today = widget.store.dueToday.length;
    if (pending.isEmpty) return '全部完成';
    final List<String> parts = <String>['待办 ${pending.length}'];
    if (over > 0) parts.add('逾期 $over');
    if (today > 0) parts.add('今天 $today');
    return parts.join(' · ');
  }

  Widget _sectionLabel(AppSurface s, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 2),
      child: Text(
        text,
        style: AppFonts.body(
          size: 12.5,
          weight: FontWeight.w700,
          color: s.muted,
          height: 1.2,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _tile(AppSurface s, TaskItem t) {
    final Color dueColor =
        t.done ? s.muted : (t.overdue ? AppColors.danger : s.muted);

    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      onTap: () => _edit(t),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 勾选完成：这是最高频操作，给足触摸面积
          GestureDetector(
            onTap: () => widget.store.toggle(t),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                t.done
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: t.done ? AppColors.success : s.muted,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  t.title,
                  style: AppFonts.body(
                    size: 15,
                    weight: FontWeight.w600,
                    color: t.done ? s.muted : s.text,
                    height: 1.35,
                  ).copyWith(
                    decoration:
                        t.done ? TextDecoration.lineThrough : null,
                    decorationColor: s.muted,
                  ),
                ),
                if (t.detail.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    t.detail.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        AppFonts.body(size: 12.5, color: s.muted, height: 1.45),
                  ),
                ],
                const SizedBox(height: 5),
                Row(
                  children: <Widget>[
                    Icon(
                      t.dueAt == null
                          ? Icons.schedule_outlined
                          : t.overdue
                              ? Icons.warning_amber_rounded
                              : Icons.schedule_rounded,
                      size: 12.5,
                      color: dueColor,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        t.dueAt == null
                            ? '未设定执行时间'
                            : t.overdue
                                ? '逾期 · ${fmtDateTime(t.dueAt!)}'
                                : fmtDateTime(t.dueAt!),
                        style: AppFonts.code(size: 11, color: dueColor),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(TaskItem? existing) async {
    final TextEditingController title =
        TextEditingController(text: existing?.title ?? '');
    final TextEditingController detail =
        TextEditingController(text: existing?.detail ?? '');
    DateTime? due = existing?.dueAt;
    final AppSurface s = AppSurface.of(context);

    final String? action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setSheet) {
          Future<void> pickDue() async {
            final DateTime now = DateTime.now();
            final DateTime? d = await showDatePicker(
              context: ctx,
              initialDate: due ?? now,
              firstDate: DateTime(now.year - 1),
              lastDate: DateTime(now.year + 5),
            );
            if (d == null || !ctx.mounted) return;
            final TimeOfDay? t = await showTimePicker(
              context: ctx,
              initialTime: TimeOfDay.fromDateTime(due ?? now),
            );
            if (!ctx.mounted) return;
            setSheet(() {
              due = DateTime(
                d.year,
                d.month,
                d.day,
                t?.hour ?? 9,
                t?.minute ?? 0,
              );
            });
          }

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: s == AppSurface.dark
                    ? AppColors.darkBg
                    : AppColors.lightBg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: s.border, width: 0.8)),
              ),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          existing == null ? '新建任务' : '编辑任务',
                          style: AppFonts.body(
                            size: 17,
                            weight: FontWeight.w700,
                            color: s.text,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (existing != null)
                        GlassIconButton(
                          icon: Icons.delete_outline_rounded,
                          tooltip: '删除',
                          size: 34,
                          iconSize: 17,
                          color: AppColors.danger,
                          onTap: () => Navigator.of(ctx).pop('delete'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView(
                      children: <Widget>[
                        _sheetInput(s, title, '任务标题', size: 16),
                        const SizedBox(height: 9),
                        _sheetInput(s, detail, '补充说明', maxLines: 4),
                        const SizedBox(height: 14),
                        Text(
                          '执行时间',
                          style: AppFonts.body(
                              size: 12.8, color: s.muted, height: 1.3),
                        ),
                        const SizedBox(height: 7),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: SurfaceCard(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                onTap: pickDue,
                                child: Row(
                                  children: <Widget>[
                                    Icon(Icons.event_rounded,
                                        size: 16,
                                        color: due == null
                                            ? s.muted
                                            : AppColors.accent),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        due == null
                                            ? '点击选择日期和时间'
                                            : fmtDateTime(due!),
                                        style: AppFonts.body(
                                          size: 13.5,
                                          color: due == null
                                              ? s.muted
                                              : s.text,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (due != null) ...<Widget>[
                              const SizedBox(width: 8),
                              GlassIconButton(
                                icon: Icons.close_rounded,
                                tooltip: '清除时间',
                                size: 40,
                                iconSize: 17,
                                onTap: () => setSheet(() => due = null),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        GlassButton(
                          label: '保存',
                          accent: true,
                          expand: true,
                          onTap: () => Navigator.of(ctx).pop('save'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (action == 'delete' && existing != null) {
      widget.store.remove(existing.id);
    } else if (action == 'save') {
      if (existing == null) {
        widget.store.create(
          title: title.text,
          detail: detail.text,
          dueAt: due,
        );
      } else {
        existing.title =
            title.text.trim().isEmpty ? existing.title : title.text.trim();
        existing.detail = detail.text;
        existing.dueAt = due;
        widget.store.update(existing);
      }
    }

    title.dispose();
    detail.dispose();
  }
}
