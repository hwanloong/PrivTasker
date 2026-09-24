import 'package:flutter/material.dart';

import '../core/productivity.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'markdown.dart';

/// 笔记编辑页。
///
/// 做成**独立页面**而不是底部弹窗，原因：
/// · 写笔记是"沉浸"行为，弹窗高度被键盘和屏幕挤压，写长内容很难受；
/// · 弹窗没法用返回手势关掉，误触遮罩还会丢内容。
///
/// 返回时自动保存（除非没改过），不需要用户记得点保存。
class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({
    super.key,
    required this.store,
    this.note,
    this.onOpenLink,
    this.initialFolderId,
  });

  final NoteStore store;

  /// null 表示新建
  final Note? note;

  final void Function(String url)? onOpenLink;

  /// 新建时的默认文件夹。用户在某个文件夹里点「+」，新笔记就该落在那儿 ——
  /// 否则他得建完再手动移一次。
  final String? initialFolderId;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _tags;

  late bool _isMarkdown;
  bool _preview = false;

  /// 当前所属文件夹。null = 未归类。
  late String? _folderId;

  /// 有没有实际改动过。没改就不写入、不刷新 updatedAt ——
  /// 否则"点开看一眼再返回"也会把这篇文章的修改时间改掉。
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final Note? n = widget.note;
    _title = TextEditingController(text: n?.title ?? '');
    _body = TextEditingController(text: n?.body ?? '');
    _tags = TextEditingController(text: n?.tags.join(' ') ?? '');
    _isMarkdown = n?.isMarkdown ?? false;
    _folderId = n?.folderId ?? widget.initialFolderId;

    _title.addListener(_markDirty);
    _body.addListener(_markDirty);
    _tags.addListener(_markDirty);
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _tags.dispose();
    super.dispose();
  }

  void _save() {
    if (!_dirty) return;

    final List<String> tagList = _tags.text
        .split(RegExp(r'\s+'))
        .where((String t) => t.trim().isNotEmpty)
        .toList();

    final Note? existing = widget.note;
    if (existing == null) {
      // 全空的新笔记不落盘 —— 避免"点进来又退出"留下一堆空笔记
      if (_title.text.trim().isEmpty && _body.text.trim().isEmpty) return;
      widget.store
          .create(
            title: _title.text,
            body: _body.text,
            tags: tagList,
          )
        ..isMarkdown = _isMarkdown
        ..folderId = _folderId;
      widget.store.saveQuietly();
    } else {
      existing.title =
          _title.text.trim().isEmpty ? existing.title : _title.text.trim();
      existing.body = _body.text;
      existing.tags = tagList;
      existing.isMarkdown = _isMarkdown;
      widget.store.touch(existing);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);

    return PopScope(
      // 返回前保存。用 PopScope 而不是只靠返回按钮 ——
      // 系统返回手势/返回键也要能触发保存。
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? _) => _save(),
      child: Scaffold(
        backgroundColor: s.isDark ? AppColors.darkBg : AppColors.lightBg,
        body: Column(
          children: <Widget>[
            _header(s),
            Expanded(
              child: _preview && _isMarkdown
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                      child: MarkdownView(
                        text: _body.text,
                        baseSize: 15,
                        onOpenLink: widget.onOpenLink,
                      ),
                    )
                  : _editor(s),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(AppSurface s) {
    final double top = MediaQuery.of(context).padding.top;

    return GlassBar(
      hairlineBottom: true,
      padding: EdgeInsets.fromLTRB(8, top + 6, 10, 10),
      child: Row(
        children: <Widget>[
          GlassIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: '返回（自动保存）',
            size: 38,
            iconSize: 19,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),

          // ---- 模式切换 ----
          _modeSwitch(s),

          const Spacer(),

          // 预览只在 Markdown 模式下有意义
          if (_isMarkdown)
            GlassIconButton(
              icon: _preview
                  ? Icons.edit_note_rounded
                  : Icons.visibility_outlined,
              tooltip: _preview ? '继续编辑' : '预览渲染结果',
              size: 38,
              iconSize: 19,
              onTap: () => setState(() => _preview = !_preview),
            ),
          if (_isMarkdown) const SizedBox(width: 6),

          if (widget.note != null)
            GlassIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: '删除',
              size: 38,
              iconSize: 19,
              color: AppColors.danger,
              onTap: _confirmDelete,
            ),
        ],
      ),
    );
  }

  /// Markdown / 纯文本 二选一
  Widget _modeSwitch(AppSurface s) {
    Widget item(String label, bool md) {
      final bool active = _isMarkdown == md;
      return GestureDetector(
        onTap: () => setState(() {
          _isMarkdown = md;
          if (!md) _preview = false; // 切到纯文本就退出预览
          _dirty = true;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: ShapeDecoration(
            color: active ? s.surface : Colors.transparent,
            shape: const StadiumBorder(),
          ),
          child: Text(
            label,
            style: AppFonts.body(
              size: 12.5,
              weight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? s.text : s.muted,
              height: 1.2,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: ShapeDecoration(
        color: s.isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          item('Markdown', true),
          item('纯文本', false),
        ],
      ),
    );
  }

  Widget _editor(AppSurface s) {
    // 正文一律用等宽字体：
    // Markdown 的语法（#、-、|、```）用等宽才对齐；纯文本场景
    // （贴日志、记代码）本来也需要等宽。
    final TextStyle bodyStyle = _isMarkdown
        ? AppFonts.code(size: 13.5, color: s.text, height: 1.65)
        : AppFonts.code(size: 13.5, color: s.text, height: 1.65);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      children: <Widget>[
        TextField(
          controller: _title,
          style: AppFonts.body(
            size: 20,
            weight: FontWeight.w700,
            color: s.text,
            height: 1.3,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintText: '标题',
            hintStyle: AppFonts.body(size: 20, color: s.muted, height: 1.3),
          ),
        ),
        const SizedBox(height: 10),
        Divider(color: s.border, height: 1),
        const SizedBox(height: 10),
        TextField(
          controller: _body,
          minLines: 12,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          style: bodyStyle,
          decoration: InputDecoration(
            isDense: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintText: _isMarkdown
                ? '# 标题\n\n- 列表项\n\n```\n代码块\n```'
                : '随手记点什么…',
            hintStyle: AppFonts.code(size: 12.5, color: s.muted),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          '标签',
          style: AppFonts.body(size: 12, color: s.muted, height: 1.3),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _tags,
          style: AppFonts.code(size: 13, color: s.text),
          decoration: InputDecoration(
            isDense: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintText: '空格分隔，例如：工作 灵感',
            hintStyle: AppFonts.code(size: 12.5, color: s.muted),
          ),
        ),

        const SizedBox(height: 18),
        // ---- 所属文件夹 ----
        Text(
          '文件夹',
          style: AppFonts.body(size: 12, color: s.muted, height: 1.3),
        ),
        const SizedBox(height: 6),
        _folderRow(s),
      ],
    );
  }

  /// 文件夹选择行。点开一个单选面板。
  ///
  /// **「未归类」是一个正经选项**，不是"没选" ——
  /// 未归类是长期存在的正常状态，用户需要能主动把笔记放回去。
  Widget _folderRow(AppSurface s) {
    final NoteFolder? cur = widget.store.folderById(_folderId);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _pickFolder,
      child: Container(
        decoration: ShapeDecoration(
          color: s.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.field),
            side: BorderSide(color: s.border, width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: <Widget>[
            Icon(
              cur == null ? Icons.inbox_outlined : Icons.folder_rounded,
              size: 16,
              color: cur == null ? s.muted : AppColors.accent,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                cur?.name ?? '未归类',
                style: AppFonts.body(size: 13.5, color: s.text, height: 1.3),
              ),
            ),
            Icon(Icons.unfold_more_rounded, size: 17, color: s.muted),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFolder() async {
    final List<NoteFolder> folders = widget.store.folders;

    final String? picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        final AppSurface s = AppSurface.of(ctx);
        return Container(
          decoration: BoxDecoration(
            color: s.isDark ? AppColors.darkBg : AppColors.lightBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: s.border, width: 0.8)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: 14),
                Text(
                  '放到哪个文件夹',
                  style: AppFonts.body(
                    size: 16,
                    weight: FontWeight.w700,
                    color: s.text,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                _folderOption(ctx, s, null, '未归类', _folderId == null),
                for (final NoteFolder f in folders)
                  _folderOption(ctx, s, f.id, f.name, _folderId == f.id),
                if (folders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                    child: Text(
                      '还没有文件夹。回笔记页点右上角的文件夹图标可以新建。',
                      style:
                          AppFonts.body(size: 12, color: s.muted, height: 1.5),
                    ),
                  )
                else
                  const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );

    if (picked == null) return;
    setState(() {
      // 用哨兵值区分"取消（null）"和"选了未归类（__none__）" ——
      // 不区分的话用户永远选不中"未归类"
      _folderId = picked == '__none__' ? null : picked;
      _dirty = true;
    });
  }

  Widget _folderOption(
    BuildContext ctx,
    AppSurface s,
    String? id,
    String name,
    bool active,
  ) {
    return InkWell(
      onTap: () => Navigator.of(ctx).pop(id ?? '__none__'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: <Widget>[
            Icon(
              id == null ? Icons.inbox_outlined : Icons.folder_rounded,
              size: 17,
              color: active ? AppColors.accent : s.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: AppFonts.body(
                  size: 14,
                  weight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? AppColors.accent : s.text,
                  height: 1.3,
                ),
              ),
            ),
            if (active)
              Icon(Icons.check_rounded,
                  size: 18, color: AppColors.accent),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final Note? n = widget.note;
    if (n == null) return;

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(
          '删除笔记',
          style: AppFonts.body(size: 16.5, weight: FontWeight.w700, height: 1.3),
        ),
        content: Text(
          '「${n.title}」将被删除，无法恢复。',
          style: AppFonts.body(size: 13.5, height: 1.6),
        ),
        actions: <Widget>[
          GlassButton(label: '取消', onTap: () => Navigator.of(ctx).pop()),
          GlassButton(
            label: '删除',
            danger: true,
            onTap: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    // 先删除再返回：返回时的 PopScope 会调 _save()，
    // 而 _dirty 此时仍为 true，若不拦住会把刚删的笔记又写回去。
    widget.store.remove(n.id);
    _dirty = false;
    if (mounted) Navigator.of(context).maybePop();
  }
}
