import 'package:flutter/material.dart';

import '../core/productivity.dart';
import '../core/store.dart';
import '../plugins/plugin.dart';
import '../shizuku/shizuku_service.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'chat_page.dart';
import 'productivity_pages.dart';

/// 应用外壳：底部三个标签（对话 / 笔记 / 任务）。
///
/// 用 IndexedStack 而不是每次重建：切回对话时要保留输入框内容、滚动位置、
/// 以及正在进行的流式回复 —— 重建会把这些全丢掉。
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.settings,
    required this.conversations,
    required this.plugins,
    required this.shizuku,
    required this.workDir,
    required this.notes,
    required this.tasks,
  });

  final Settings settings;
  final ConversationStore conversations;
  final PluginStore plugins;
  final ShizukuService shizuku;
  final String workDir;
  final NoteStore notes;
  final TaskStore tasks;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    widget.tasks.addListener(_onChange);
    widget.notes.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.tasks.removeListener(_onChange);
    widget.notes.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);

    return Scaffold(
      backgroundColor:
          s.isDark ? AppColors.darkBg : AppColors.lightBg,
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          ChatPage(
            settings: widget.settings,
            conversations: widget.conversations,
            plugins: widget.plugins,
            shizuku: widget.shizuku,
            workDir: widget.workDir,
            notes: widget.notes,
            tasks: widget.tasks,
          ),
          NotesPage(store: widget.notes),
          TasksPage(store: widget.tasks),
        ],
      ),
      bottomNavigationBar: _nav(context, s),
    );
  }

  Widget _nav(BuildContext context, AppSurface s) {
    // 待办数量做成角标：不用切过去就知道有没有事
    final int pending = widget.tasks.pending.length;
    final int overdue = widget.tasks.overdue.length;

    return GlassBar(
      hairlineTop: true,
      padding: EdgeInsets.fromLTRB(
        8,
        6,
        8,
        6 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: <Widget>[
          _navItem(
            s,
            index: 0,
            icon: Icons.forum_outlined,
            activeIcon: Icons.forum_rounded,
            label: '对话',
          ),
          _navItem(
            s,
            index: 1,
            icon: Icons.sticky_note_2_outlined,
            activeIcon: Icons.sticky_note_2_rounded,
            label: '笔记',
            badge: widget.notes.items.isEmpty
                ? null
                : widget.notes.items.length,
          ),
          _navItem(
            s,
            index: 2,
            icon: Icons.check_circle_outline_rounded,
            activeIcon: Icons.check_circle_rounded,
            label: '任务',
            badge: pending == 0 ? null : pending,
            alert: overdue > 0,
          ),
        ],
      ),
    );
  }

  Widget _navItem(
    AppSurface s, {
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    int? badge,
    bool alert = false,
  }) {
    final bool active = _index == index;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.field),
        onTap: () => setState(() => _index = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // M3 NavigationBar 的「胶囊型选中指示器」——
              // 这是 Material You 最好认的一个特征：选中项背后有一块
              // secondaryContainer 色的药丸，图标和文字都换成对应前景色。
              AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    // 宽度**必须固定**。之前是 `active ? 60 : 0`，
                    // 未选中时容器宽度为 0，里面的图标被压成 0 宽 ——
                    // 三个项的图标位置就全错开了。
                    // M3 的指示器本来就是定宽的，只让**颜色**做动画。
                    width: 60,
                    height: 30,
                    decoration: ShapeDecoration(
                      color: active
                          ? scheme.secondaryContainer
                          : Colors.transparent,
                      shape: const StadiumBorder(),
                    ),
                    child: Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          Icon(
                            active ? activeIcon : icon,
                            size: 22,
                            color: active
                                ? scheme.onSecondaryContainer
                                : scheme.onSurfaceVariant,
                          ),
                          if (badge != null)
                            Positioned(
                              right: -11,
                              top: -6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4.5, vertical: 1),
                                constraints: const BoxConstraints(minWidth: 15),
                                decoration: BoxDecoration(
                                  // 有逾期任务时角标变红，这是唯一需要立刻注意的状态
                                  color: alert ? scheme.error : scheme.primary,
                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                ),
                                child: Text(
                                  badge > 99 ? '99+' : '$badge',
                                  textAlign: TextAlign.center,
                                  style: AppFonts.body(
                                    size: 9.5,
                                    weight: FontWeight.w700,
                                    color: alert
                                        ? scheme.onError
                                        : scheme.onPrimary,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: AppFonts.body(
                      size: 11,
                      weight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                      height: 1.2,
                    ),
                  ),
                ],
          ),
        ),
      ),
    );
  }
}

/// 各页面共用的头部。
///
/// 抽出来是为了让三个标签的头部样式完全一致 ——
/// 否则迟早会出现「对话页的标题 22px、笔记页 20px」这种细碎的不一致。
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.leading,
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);
    final double topInset = MediaQuery.of(context).padding.top;

    return GlassBar(
      hairlineBottom: true,
      padding: EdgeInsets.fromLTRB(18, topInset + 6, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      style: AppFonts.body(
                        size: 22,
                        weight: FontWeight.w700,
                        color: s.text,
                        height: 1.2,
                      ),
                    ),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.body(
                            size: 12.5, color: s.muted, height: 1.25),
                      ),
                    ],
                  ],
                ),
              ),
              ?leading,
              ...actions,
            ],
          ),
          if (bottom != null) ...<Widget>[
            const SizedBox(height: 10),
            bottom!,
          ],
        ],
      ),
    );
  }
}

/// 空状态提示（三个页面共用）
class EmptyHint extends StatelessWidget {
  const EmptyHint({
    super.key,
    required this.icon,
    required this.title,
    required this.desc,
  });

  final IconData icon;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 38, color: s.muted.withValues(alpha: 0.5)),
            const SizedBox(height: 14),
            Text(
              title,
              style: AppFonts.body(
                size: 15,
                weight: FontWeight.w600,
                color: s.text,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              desc,
              textAlign: TextAlign.center,
              style: AppFonts.body(size: 13, color: s.muted, height: 1.55),
            ),
          ],
        ),
      ),
    );
  }
}
