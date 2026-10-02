import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

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
      backgroundColor: s.isDark ? AppColors.darkBg : AppColors.lightBg,
      // 让 body 延伸到标签栏**后面**。
      //
      // 这不是装饰性的：玻璃靠**折射背后的东西**成立，背后什么都没有的话，
      // 它看起来就是一块平的半透明色块 —— 用户会觉得"玻璃效果没生效"。
      // 打开这个之后，消息和列表会从玻璃底下滚过去，折射是真的。
      extendBody: true,
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

  /// 底部标签栏：液态玻璃的**悬浮胶囊**。
  ///
  /// 底部标签栏：**液态玻璃**（`GlassTabBar.bottom`）。
  ///
  /// ## 为什么必须显式传 `settings:`
  ///
  /// 之前我为了"避开发白"换成了手写的 `BackdropFilter` —— 结果把液态效果
  /// 也一起砍掉了。用户的原话是"你把液态效果修没了"。那是错的解法：
  /// 该修的是**颜色**，不是实现。
  ///
  /// 发白的根因：包为深色模式准备的玻璃底色是 `glassColor: 白色 8%`。
  /// 在纯黑页面上这个"8% 白"叠加 shader 的高光/色差之后，看起来就是发白。
  ///
  /// 所以这里**显式给一套完整的 settings**，把深色下的底色换成一个
  /// 明确的深色（`#1C1C1E` 的 55%），其余参数沿用包为亮/暗分别调好的值。
  ///
  /// > 注意必须是**完整**的一套。`LiquidGlassSettings` 的构造参数全都带默认值，
  /// > 只传其中几个等于把其余几十个（lightIntensity、bodyMode…）重置成构造
  /// > 默认值 —— 那是砸掉，不是微调。（这一条我踩过一次。）
  Widget _nav(BuildContext context, AppSurface s) {
    final int pending = widget.tasks.pending.length;
    final int overdue = widget.tasks.overdue.length;
    final bool dark = s.isDark;
    final Color idle = s.muted;

    return Padding(
      // 左右留 10：液态玻璃标签栏是**浮**在内容上的，四周要露出页面底色
      // 才看得出它是一块玻璃。贴边通栏会把这个效果抹掉（也试过，被否了）。
      padding: EdgeInsets.fromLTRB(
        10,
        0,
        10,
        6 + MediaQuery.of(context).padding.bottom,
      ),
      child: GlassTabBar.bottom(
        // ---- 高度 ----
        //
        // 默认 barHeight 64 + verticalPadding 20×2 = 104，太高，
        // 会把输入栏和它之间的间距撑开；而上一版收到 56 + 6 = 68 又太矮
        // （"上下太窄"）。64 + 10×2 = 84 是这两次反馈的折中。
        barHeight: 64,
        verticalPadding: 10,
        // ---- 颜色：发白的修复在这里 ----
        settings: LiquidGlassSettings(
          // **深色下换成明确的深色玻璃**，而不是包默认的"白色 8%"。
          // 亮色保持包的默认值不变。
          glassColor: dark
              ? const Color.fromRGBO(28, 28, 30, 0.55)
              : const Color.fromRGBO(210, 220, 240, 0.12),
          // 以下都是包为亮/暗分别调好的值，原样保留。
          thickness: dark ? 10 : 12,
          blur: dark ? 4 : 5,
          lightAngle: 2.356,
          lightIntensity: dark ? 0.7 : 0.85,
          ambientStrength: dark ? 0.0 : 0.15,
          refractiveIndex: 1.2,
          saturation: 1.2,
          chromaticAberration: dark ? 0.01 : 0.02,
        ),
        tabs: <GlassTab>[
          GlassTab(
            icon: _tabIcon(
              icon: Icons.forum_outlined,
              activeIcon: Icons.forum_rounded,
              active: _index == 0,
              color: _index == 0 ? AppColors.accent : idle,
            ),
            activeIcon: _tabIcon(
              icon: Icons.forum_outlined,
              activeIcon: Icons.forum_rounded,
              active: true,
              color: AppColors.accent,
            ),
            label: '对话',
          ),
          // 笔记**不带角标**。
          //
          // 原来挂了一个"笔记条数"的红色角标，两个问题：
          // · 笔记条数不是**待处理**的东西 —— 看一眼不会产生任何行动。
          // · 角标用的是全局 danger 红，那是"出事了"的语言。
          //   一个纯数量提示天天报警，久了用户就不看角标了，
          //   等真正的逾期提示出现时也照样忽略。
          //
          // 任务角标保留：那个是**待办数**，逾期时会变红，有行动含义。
          GlassTab(
            icon: _tabIcon(
              icon: Icons.sticky_note_2_outlined,
              activeIcon: Icons.sticky_note_2_rounded,
              active: _index == 1,
              color: _index == 1 ? AppColors.accent : idle,
            ),
            activeIcon: _tabIcon(
              icon: Icons.sticky_note_2_outlined,
              activeIcon: Icons.sticky_note_2_rounded,
              active: true,
              color: AppColors.accent,
            ),
            label: '笔记',
          ),
          GlassTab(
            icon: _tabIcon(
              icon: Icons.check_circle_outline_rounded,
              activeIcon: Icons.check_circle_rounded,
              active: _index == 2,
              color: _index == 2 ? AppColors.accent : idle,
              badge: pending == 0 ? null : pending,
              alert: overdue > 0,
            ),
            activeIcon: _tabIcon(
              icon: Icons.check_circle_outline_rounded,
              activeIcon: Icons.check_circle_rounded,
              active: true,
              color: AppColors.accent,
              badge: pending == 0 ? null : pending,
              alert: overdue > 0,
            ),
            label: '任务',
          ),
        ],
        selectedIndex: _index,
        onTabSelected: (int i) => setState(() => _index = i),
        // 指示器和外层胶囊**同心**：给足够大的值让 Flutter 夹到半高。
        // 这个控件**确实**对哨兵值有特判（`GlassButton` 没有，那边不能用）。
        indicatorBorderRadius: 100,
        indicatorExpansion:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        horizontalPadding: 22,
        // 选中 = 图标和文字变成强调色，未选中是中灰。这就是 iOS 标签栏的做法。
        selectedIconColor: AppColors.accent,
        selectedLabelColor: AppColors.accent,
        unselectedIconColor: idle,
        unselectedLabelColor: idle,
      ),
    );
  }

  /// 标签图标，可带角标。
  ///
  /// `GlassTab.icon` 收的是 Widget，角标直接叠在图标上。代价是**颜色必须自己给**：
  /// 平时 `Icon` 会从父级 `IconTheme` 继承选中/未选中的颜色，
  /// 套了一层 `Stack` 之后这条路就断了，所以下面每个图标都要显式传 color。
  Widget _tabIcon({
    required IconData icon,
    required IconData activeIcon,
    required bool active,
    required Color color,
    int? badge,
    bool alert = false,
  }) {
    final Widget glyph =
        Icon(active ? activeIcon : icon, size: 24, color: color);
    if (badge == null) return glyph;

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        glyph,
        Positioned(
          right: -11,
          top: -5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16),
            decoration: BoxDecoration(
              color: AppColors.danger,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              badge > 99 ? '99+' : '$badge',
              textAlign: TextAlign.center,
              style: AppFonts.body(
                size: 9.5,
                weight: FontWeight.w600,
                color: Colors.white,
                height: 1.2,
              ),
            ),
          ),
        ),
      ],
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
      padding: EdgeInsets.fromLTRB(18, topInset + 8, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              // ---- `leading` 必须排在最前（左上角）----
              //
              // 这是个**位置性**的东西，不是审美偏好：返回按钮在左上角是
              // Android 和 iOS 共同的肌肉记忆，用户闭着眼也知道往哪点。
              //
              // 之前 `leading` 被排在 `Expanded(标题)` **后面**，于是它跑到了
              // 右上角 —— 每个用 AppHeader 的页面（设置、TeenSpace、工作空间、
              // 记忆、规则、Python 控制台、笔记编辑、浏览器）返回键全在右边。
              // 一处顺序写错，八处页面一起错，而且看起来像"每个页面都做错了"。
              ?leading,
              if (leading != null) const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      style: AppFonts.body(
                        // 页面大标题。曾经是 25 + w700 —— 那是照搬 iOS 大标题的
                        // 字号，但没考虑中文：同样磅值下汉字比拉丁字母的视觉重量
                        // 大得多，25px 的中文标题会显得又粗又占地方。
                        // 收到 22 + w600 之后层级还在，但不再压着下面的内容。
                        size: 22,
                        weight: FontWeight.w600,
                        color: s.text,
                        height: 1.2,
                        // iOS 大标题的负字距（tracking）是 -0.4pt 左右，
                        // 标题越大字距越收 —— 不收的话会显得松散、不像 iOS。
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.body(
                            size: 13, color: s.muted, height: 1.25),
                      ),
                    ],
                  ],
                ),
              ),
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
