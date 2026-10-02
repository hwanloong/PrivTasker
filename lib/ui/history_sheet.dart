import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/store.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';

Future<void> showHistorySheet(
  BuildContext context, {
  required ConversationStore store,
}) {
  // **刻意用普通的 showModalBottomSheet，不用液态玻璃。**
  //
  // 这一页是一列会话，通篇都是内容（白卡片），没有"浮在内容之上的控制层"。
  // 玻璃的意义是让背后的东西透出来，而这里背后就是聊天的背景 ——
  // 透出来只会让一列卡片浮在半透明的底上，读起来更费劲，也不好看。
  //
  // 玻璃留给真正的导航层（标签栏、按钮、别的面板）。
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
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
                          weight: FontWeight.w600,
                          color: s.text,
                          height: 1.2,
                        ),
                      ),
                    ),
                    // 「新对话」就是一个加号。
                    //
                    // 原来是个带文字的强调色胶囊按钮，在标题行里太重了 ——
                    // 它和左边的「历史记录」标题抢注意力，而它其实只是个
                    // 常规动作。一个加号图标够了：加号在列表语境里就是"新建"，
                    // 不需要文字解释。
                    GlassIconButton(
                      icon: Icons.add_rounded,
                      tooltip: '新对话',
                      size: 36,
                      iconSize: 20,
                      color: AppColors.accent,
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
                    // **shrinkWrap**：面板的高度跟着内容走，而不是一律撑到
                    // 上限。
                    //
                    // 配上玻璃面板之后这件事变得明显了：以前底色是灰的，
                    // 撑满看不出；现在半透明，"只有一条会话却占了八成屏"
                    // 就是一大片空玻璃。
                    //
                    // 会话很多时它仍然受上面的 maxHeight 约束，会正常滚动。
                    shrinkWrap: true,
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
          style: AppFonts.body(size: 16.5, weight: FontWeight.w600, height: 1.3),
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
