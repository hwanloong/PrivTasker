import 'package:flutter/material.dart';

import '../core/productivity.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'home_shell.dart';
import 'note_editor_page.dart';

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

  /// 当前选中的标签筛选。null = 不筛选。
  ///
  /// 和搜索是**叠加**关系而不是二选一：选了标签之后再搜关键词，
  /// 是在这个标签范围内搜。这样"找工作时笔记里提到 X 的那条"才成立。
  String? _activeTag;

  /// 当前打开的文件夹。**null = 根级**（显示文件夹列表 + 未归类的笔记）。
  String? _openFolderId;

  bool get _atRoot => _openFolderId == null;

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
    if (!mounted) return;
    // 标签可能因为编辑/删除而不复存在，筛选项要跟着失效，
    // 否则会停在"筛一个已经不存在的标签"然后显示空列表
    if (_activeTag != null && !_allTags().contains(_activeTag)) {
      _activeTag = null;
    }
    // 文件夹被删掉时同理：还停在那个文件夹里会显示一片空白
    if (_openFolderId != null &&
        widget.store.folderById(_openFolderId) == null) {
      _openFolderId = null;
    }
    setState(() {});
  }

  /// 当前范围内出现过的标签。
  ///
  /// **按文件夹取而不是取全部** —— 在"工作"文件夹里列出"菜谱"标签
  /// 只会让人困惑（点了必然是空列表）。
  List<String> _allTags() =>
      widget.store.tagsIn(folderId: _atRoot ? null : _openFolderId);

  /// 当前要显示的笔记。
  ///
  /// 根级只显示**未归类的** —— 归了类的在文件夹里，重复显示会让
  /// 根级变成一个越来越长的混合列表，那文件夹就白做了。
  List<Note> _visibleNotes() => widget.store.filter(
        folderId: _atRoot ? null : _openFolderId,
        keyword: _search.text,
        tag: _activeTag,
      );

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);
    final List<String> tags = _allTags();
    final List<Note> list = _visibleNotes();
    final int total = widget.store.items.length;
    final NoteFolder? folder = widget.store.folderById(_openFolderId);

    return Scaffold(
      backgroundColor:
          s.isDark ? AppColors.darkBg : AppColors.lightBg,
      body: Column(
        children: <Widget>[
          AppHeader(
            // 进了文件夹就显示文件夹名，并且给一个返回根级的箭头 ——
            // 否则用户会不知道自己现在在哪一层
            title: folder?.name ?? '笔记',
            leading: folder == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: GlassIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: '返回全部',
                      size: 36,
                      iconSize: 18,
                      onTap: () => setState(() {
                        _openFolderId = null;
                        _activeTag = null;
                        _search.clear();
                      }),
                    ),
                  ),
            subtitle: total == 0
                ? '还没有笔记'
                : _subtitle(folder, list.length, total),
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
              // 在文件夹里「+」是新建笔记；在根级多一个建文件夹的入口
              if (folder == null)
                GlassIconButton(
                  icon: Icons.create_new_folder_outlined,
                  tooltip: '新建文件夹',
                  size: 36,
                  iconSize: 18,
                  onTap: _newFolder,
                ),
              if (folder == null) const SizedBox(width: 6),
              GlassIconButton(
                icon: Icons.add_rounded,
                tooltip: '新建笔记',
                size: 36,
                iconSize: 18,
                onTap: () => _edit(null),
              ),
            ],
            bottom: (tags.isEmpty && !_searching)
                ? null
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (_searching)
                        Container(
                          decoration: BoxDecoration(
                            color: s.surface,
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                            border: Border.all(color: s.border, width: 0.9),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 2),
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
                              hintStyle:
                                  AppFonts.body(size: 14, color: s.muted),
                            ),
                          ),
                        ),
                      // ---- 标签筛选 ----
                      //
                      // 横向滚动而不是换行：标签一多换行会把头部撑得很高，
                      // 正文可视区域被压缩。横向滚动的高度永远只有一行。
                      if (tags.isNotEmpty) ...<Widget>[
                        if (_searching) const SizedBox(height: 9),
                        SizedBox(
                          height: 32,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.zero,
                            children: <Widget>[
                              // 「全部」只在有筛选时才出现 ——
                              // 没筛选时它没有任何作用，白占一个位置
                              if (_activeTag != null) ...<Widget>[
                                _tagChip(s, '全部', null, count: _scopeCount()),
                                const SizedBox(width: 7),
                              ],
                              for (final String t in tags) ...<Widget>[
                                _tagChip(
                                  s,
                                  t,
                                  t,
                                  count: widget.store
                                      .filter(
                                        folderId:
                                            _atRoot ? null : _openFolderId,
                                        tag: t,
                                      )
                                      .length,
                                ),
                                const SizedBox(width: 7),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              children: <Widget>[
                // 根级先列文件夹，再列未归类的笔记。
                // **顺序很重要**：文件夹是"分类入口"，放在笔记上面才符合
                // "先选类别再看内容"的直觉。
                if (_atRoot && widget.store.folders.isNotEmpty) ...<Widget>[
                  for (final NoteFolder f in widget.store.folders)
                    _folderTile(s, f),
                  const SizedBox(height: 6),
                ],

                // 未归类那一栏的标题。只在**两种东西同时存在**时才显示 ——
                // 没有文件夹时这行标题毫无意义（所有笔记都未归类）
                if (_atRoot && widget.store.folders.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      '未归类 ${widget.store.unfiledCount} 条',
                      style: AppFonts.body(
                        size: 12.5,
                        weight: FontWeight.w600,
                        color: s.muted,
                        height: 1.2,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),

                if (list.isEmpty && widget.store.folders.isEmpty)
                  EmptyHint(
                    icon: Icons.sticky_note_2_outlined,
                    title: _search.text.trim().isEmpty ? '还没有笔记' : '没有匹配的笔记',
                    desc: _search.text.trim().isEmpty
                        ? '点右上角「+」新建。\n也可以直接对 Agent 说「记一下……」，它会替你写进来。'
                        : '换个关键词试试。',
                  )
                else if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      _search.text.trim().isEmpty
                          ? '这一层还没有笔记'
                          : '没有匹配的笔记',
                      textAlign: TextAlign.center,
                      style:
                          AppFonts.body(size: 13, color: s.muted, height: 1.5),
                    ),
                  )
                else
                  for (final Note n in list) _tile(s, n),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 当前范围（文件夹或未归类）里的笔记总数，用于标签条的「全部」
  int _scopeCount() =>
      widget.store.filter(folderId: _atRoot ? null : _openFolderId).length;

  /// 头部副标题
  String _subtitle(NoteFolder? folder, int shown, int total) {
    if (folder == null) {
      final int unfiled = widget.store.unfiledCount;
      if (widget.store.folders.isEmpty) return '共 $total 条';
      return '${widget.store.folders.length} 个文件夹 · 未归类 $unfiled 条';
    }
    final String scope = '$shown 条';
    return _activeTag == null ? scope : '筛选「$_activeTag」· $scope';
  }

  /// 文件夹卡片。点进去，长按改名/删除。
  Widget _folderTile(AppSurface s, NoteFolder f) {
    final int n = widget.store.countInFolder(f.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        onTap: () => setState(() {
          _openFolderId = f.id;
          _activeTag = null;
          _search.clear();
          _searching = false;
        }),
        child: Row(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              decoration: ShapeDecoration(
                color: AppColors.accent.withValues(alpha: 0.13),
                shape: const CircleBorder(),
              ),
              child: Icon(Icons.folder_rounded,
                  size: 17, color: AppColors.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                f.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.body(
                  size: 14.5,
                  weight: FontWeight.w600,
                  color: s.text,
                  height: 1.3,
                ),
              ),
            ),
            Text('$n', style: AppFonts.code(size: 12, color: s.muted)),
            const SizedBox(width: 4),
            // 长按不是好交互（没人会去试），所以给一个明确的「⋯」
            GlassIconButton(
              icon: Icons.more_horiz_rounded,
              tooltip: '重命名 / 删除',
              size: 32,
              iconSize: 17,
              onTap: () => _folderMenu(f),
            ),
          ],
        ),
      ),
    );
  }

  /// 文件夹的重命名 / 删除
  Future<void> _folderMenu(NoteFolder f) async {
    final int n = widget.store.countInFolder(f.id);

    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) {
        final AppSurface s = AppSurface.of(ctx);
        return SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: 14),
                Text(
                  f.name,
                  style: AppFonts.body(
                    size: 16,
                    weight: FontWeight.w600,
                    color: s.text,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.drive_file_rename_outline_rounded,
                      size: 20),
                  title: const Text('重命名'),
                  onTap: () => Navigator.of(ctx).pop('rename'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                      size: 20, color: AppColors.danger),
                  title: Text(
                    // **把后果写清楚**：这个数字是用户决定要不要删的关键依据，
                    // 藏起来的话他只能靠猜
                    n == 0 ? '删除文件夹' : '删除文件夹（$n 条笔记会变成未归类）',
                    style: const TextStyle(color: AppColors.danger),
                  ),
                  onTap: () => Navigator.of(ctx).pop('delete'),
                ),
                const SizedBox(height: 10),
              ],
            ),
        );
      },
    );

    if (!mounted) return;
    if (action == 'rename') {
      final TextEditingController c = TextEditingController(text: f.name);
      final String? name = await _promptText('重命名文件夹', c, '文件夹名');
      c.dispose();
      if (name != null && name.trim().isNotEmpty) {
        widget.store.renameFolder(f, name);
      }
    } else if (action == 'delete') {
      // 二次确认里**再次强调"笔记不会删"** ——
      // 这是用户最担心的事，不说清他会不敢删
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text('删除文件夹',
              style:
                  AppFonts.body(size: 16.5, weight: FontWeight.w600, height: 1.3)),
          content: mdText(
            '「${f.name}」将被删除。\n\n'
            '里面的 $n 条笔记**不会被删除**，它们会变成「未归类」，'
            '仍然可以在根级看到。',
            style: AppFonts.body(size: 13.5, height: 1.65),
          ),
          actions: <Widget>[
            GlassButton(label: '取消', onTap: () => Navigator.of(ctx).pop()),
            GlassButton(
              label: '删除文件夹',
              danger: true,
              onTap: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      );
      if (ok == true) widget.store.deleteFolder(f.id);
    }
  }

  Future<void> _newFolder() async {
    final TextEditingController c = TextEditingController();
    final String? name = await _promptText('新建文件夹', c, '文件夹名');
    c.dispose();
    if (name != null && name.trim().isNotEmpty) {
      widget.store.createFolder(name);
    }
  }

  /// 通用的单行文本输入弹窗
  Future<String?> _promptText(
    String title,
    TextEditingController c,
    String hint,
  ) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext ctx) {
        final AppSurface s = AppSurface.of(ctx);
        return AlertDialog(
          title: Text(title,
              style:
                  AppFonts.body(size: 16.5, weight: FontWeight.w600, height: 1.3)),
          content: Container(
            decoration: ShapeDecoration(
              color: s.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.field),
                side: BorderSide(color: s.border, width: 1),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: c,
              autofocus: true,
              onSubmitted: (String v) => Navigator.of(ctx).pop(v),
              style: AppFonts.body(size: 14.5, color: s.text),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintText: hint,
                hintStyle: AppFonts.body(size: 14, color: s.muted),
              ),
            ),
          ),
          actions: <Widget>[
            GlassButton(label: '取消', onTap: () => Navigator.of(ctx).pop()),
            GlassButton(
              label: '确定',
              accent: true,
              onTap: () => Navigator.of(ctx).pop(c.text),
            ),
          ],
        );
      },
    );
  }

  /// 一个标签筛选按钮。
  ///
  /// [value] 为 null 表示「全部」。显示条数是因为筛选后最想知道的是
  /// "这个标签下有多少东西"，不给数字的话点进去可能是个空列表。
  Widget _tagChip(AppSurface s, String label, String? value,
      {required int count}) {
    final bool active = _activeTag == value;
    final Color fg = active ? AppColors.accent : s.muted;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _activeTag = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: ShapeDecoration(
          color: active
              ? AppColors.accent.withValues(alpha: 0.12)
              : s.surface,
          shape: const StadiumBorder(),
          // 选中的加一圈描边 —— 只靠底色在小屏上不够明显
          shadows: null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: AppFonts.body(
                size: 12.5,
                weight: active ? FontWeight.w600 : FontWeight.w500,
                color: fg,
                height: 1.2,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: AppFonts.code(size: 10.5, color: fg),
            ),
          ],
        ),
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

  /// 打开笔记编辑页。
  ///
  /// 改成**独立页面**而不是底部弹窗：写笔记是沉浸行为，
  /// 弹窗高度被键盘和屏幕挤压，写长内容很难受，误触遮罩还会丢内容。
  /// 编辑页自己在返回时保存。
  Future<void> _edit(Note? existing) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => NoteEditorPage(
          store: widget.store,
          note: existing,
          // 在某个文件夹里点「+」，新笔记直接落在那儿 ——
          // 否则用户还得建完再手动移一次
          initialFolderId: existing == null && !_atRoot ? _openFolderId : null,
        ),
      ),
    );
    if (mounted) setState(() {});
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
      borderRadius: BorderRadius.circular(AppRadius.code),
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
          s.isDark ? AppColors.darkBg : AppColors.lightBg,
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
          weight: FontWeight.w600,
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
                            weight: FontWeight.w600,
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
