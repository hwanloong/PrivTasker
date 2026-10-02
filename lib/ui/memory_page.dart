import 'package:flutter/material.dart';

import '../core/memory.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'home_shell.dart';

/// 记忆管理页。
///
/// **为什么是独立页面而不是设置里的一个分组**：记忆是**累积**的。
/// 攒到几十条之后需要一个能滚动、能逐条删的完整页面；塞在设置面板里
/// 最后会变成一个谁也翻不完的列表。
///
/// 开关留在设置里（"要不要带上这些"是设置），这个页面只管内容
/// （"记住了什么、要删哪条"）。两件事混在一处会让人不敢碰。
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key, required this.store});

  final MemoryStore store;

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
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
    final List<MemoryItem> items = widget.store.items;

    return Scaffold(
      backgroundColor: s.isDark ? AppColors.darkBg : AppColors.lightBg,
      body: Column(
        children: <Widget>[
          AppHeader(
            title: '记忆',
            subtitle: items.isEmpty
                ? '还没有记住任何事'
                : '${items.length} 条 · 每轮对话都会带上',
            leading: GlassIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              tooltip: '返回',
              size: 38,
              iconSize: 19,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            actions: <Widget>[
              GlassIconButton(
                icon: Icons.add_rounded,
                tooltip: '手动加一条',
                size: 38,
                iconSize: 20,
                onTap: _addManual,
              ),
              if (items.isNotEmpty) ...<Widget>[
                const SizedBox(width: 6),
                GlassIconButton(
                  icon: Icons.delete_sweep_outlined,
                  tooltip: '清空全部',
                  size: 38,
                  iconSize: 18,
                  onTap: () => _confirmClear(context),
                ),
              ],
            ],
          ),
          Expanded(
            child: items.isEmpty
                ? const EmptyHint(
                    icon: Icons.psychology_outlined,
                    title: '还没有记忆',
                    desc: '聊天时 agent 会自己判断哪些是"会长期有效的事实"并记下来，'
                        '比如你住在哪、习惯用什么工具。\n'
                        '你也可以点右上角手动加一条。',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                    itemCount: items.length,
                    itemBuilder: (BuildContext context, int i) =>
                        _tile(s, items[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tile(AppSurface s, MemoryItem m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    m.text,
                    style: AppFonts.body(
                        size: 13.5, color: s.text, height: 1.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _fmtDate(m.createdAt),
                    style: AppFonts.body(size: 11, color: s.muted, height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            GlassIconButton(
              icon: Icons.close_rounded,
              tooltip: '删掉这条',
              size: 32,
              iconSize: 16,
              color: AppColors.danger,
              onTap: () => widget.store.remove(m.id),
            ),
          ],
        ),
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _fmtDate(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

  Future<void> _addManual() async {
    final TextEditingController c = TextEditingController();
    final String? text = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('加一条记忆'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          style: AppFonts.body(size: 14),
          decoration: const InputDecoration(
            hintText: '比如：用户住在杭州',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(c.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    c.dispose();

    if (text == null || text.trim().isEmpty) return;
    final String? err = widget.store.add(text);
    if (!mounted) return;
    if (err != null) {
      // 失败原因（太长、超上限）必须说出来。沉默着不保存，
      // 用户只会以为应用坏了。
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _confirmClear(BuildContext context) async {
    final int n = widget.store.items.length;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('清空全部记忆？'),
        content: mdText('$n 条记忆会被永久删除，**没有回收站**。\n'
            '这不会影响笔记和对话记录。', style: AppFonts.body(size: 14)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) widget.store.clear();
  }
}
