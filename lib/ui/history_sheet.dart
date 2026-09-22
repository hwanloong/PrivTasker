import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/store.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';

Future<void> showHistorySheet(
  BuildContext context, {
  required ConversationStore store,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext ctx) => _HistorySheet(store: store),
  );
}

class _HistorySheet extends StatefulWidget {
  const _HistorySheet({required this.store});

  final ConversationStore store;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
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
    final List<Conversation> list = widget.store.sorted;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: BoxDecoration(
        color: s == AppSurface.dark ? AppColors.darkBg : AppColors.lightBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: s.border, width: 0.8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 12),
            child: Column(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: s.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    const SizedBox(width: 18),
                    Expanded(
                      child: Text(
                        '历史记录',
                        style: AppFonts.body(
                          size: 17,
                          weight: FontWeight.w700,
                          color: s.text,
                          height: 1.2,
                        ),
                      ),
                    ),
                    GlassButton(
                      label: '新对话',
                      icon: Icons.add_rounded,
                      accent: true,
                      fontSize: 13,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 8),
                      onTap: () {
                        widget.store.createNew();
                        Navigator.of(context).pop();
                      },
                    ),
                    if (list.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 7),
                      GlassIconButton(
                        icon: Icons.delete_sweep_outlined,
                        tooltip: '清空全部',
                        size: 36,
                        iconSize: 17,
                        onTap: () => _confirmClear(context),
                      ),
                    ],
                    const SizedBox(width: 14),
                  ],
                ),
              ],
            ),
          ),
          Flexible(
            child: list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 50),
                    child: Text(
                      '还没有历史对话',
                      style: AppFonts.body(size: 14, color: s.muted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: list.length,
                    itemBuilder: (BuildContext context, int i) {
                      final Conversation c = list[i];
                      final bool active = c.id == widget.store.currentId;
                      return SurfaceCard(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                        borderColor:
                            active ? AppColors.accent : null,
                        onTap: () {
                          widget.store.select(c.id);
                          Navigator.of(context).pop();
                        },
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    c.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppFonts.body(
                                      size: 14.2,
                                      weight: FontWeight.w600,
                                      color: s.text,
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${c.messages.length} 条 · ${_ago(c.updatedAt)}',
                                    style: AppFonts.body(
                                      size: 11.8,
                                      color: s.muted,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close_rounded,
                                  size: 17, color: s.muted),
                              tooltip: '删除',
                              onPressed: () => widget.store.remove(c.id),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(
          '清空全部历史？',
          style: AppFonts.body(size: 16.5, weight: FontWeight.w700, height: 1.3),
        ),
        content: Text(
          '所有会话记录都会被删除，且无法恢复。',
          style: AppFonts.body(size: 13.5, height: 1.6),
        ),
        actions: <Widget>[
          GlassButton(
            label: '取消',
            onTap: () => Navigator.of(ctx).pop(false),
          ),
          GlassButton(
            label: '清空',
            danger: true,
            onTap: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (ok == true) {
      widget.store.clearAll();
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  static String _ago(DateTime t) {
    final Duration d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    if (d.inDays < 30) return '${d.inDays} 天前';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
  }
}
