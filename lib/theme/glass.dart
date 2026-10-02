import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

import 'app_theme.dart';

// ============================================================ 行内文本

/// 渲染 `**行内粗体**` 和 `` `行内代码` `` 的 Text。
///
/// **为什么需要它**：项目里到处在 UI 文案里写 `**重点**`、`` `命令` ``
/// （写 markdown 的习惯），但普通 `Text` 不解析 markdown ——
/// 星号和反引号会**原样显示**出来。界面上出现一堆 `**` 和 `` ` ``，
/// 看起来就像哪里坏了，而写的人完全不会意识到。
///
/// 只处理这两种行内标记，不引完整的 markdown 渲染器：
/// UI 文案需要的就这两种，而完整解析器会带进块级排版（标题、列表、代码块），
/// 那些塞在一行提示里只会更乱。真正需要完整 markdown 的地方用 `MarkdownView`。
///
/// 注意区分：**给模型看的**工具描述、提示词里的 `**` 是正确的，不要动 ——
/// 那些文本是发给模型的，它读 markdown。
Widget mdText(
  String text, {
  required TextStyle style,
  TextAlign? textAlign,
  int? maxLines,
  TextOverflow? overflow,
}) {
  final RegExp re = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`', dotAll: true);
  final List<InlineSpan> spans = <InlineSpan>[];
  int last = 0;

  for (final RegExpMatch m in re.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start)));
    }

    final String? bold = m.group(1);
    if (bold != null) {
      spans.add(TextSpan(
        text: bold,
        // 封顶 w600：本项目的字重约定就是最高 semibold
        // （见 README 的「字号与字重」）。再粗一档就压过正文了。
        style: const TextStyle(fontWeight: FontWeight.w600),
      ));
    } else {
      // 行内代码：等宽、比正文小一号，**不换颜色** ——
      // 换了会在灰字提示里突然冒出一块彩色，反而更乱。
      spans.add(TextSpan(
        text: m.group(2),
        style: AppFonts.code(
          size: (style.fontSize ?? 13) - 1,
          color: style.color,
        ),
      ));
    }
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));

  // 没有标记时退化成普通 Text 的行为（spans 只有一段），不必特判。
  return Text.rich(
    TextSpan(style: style, children: spans),
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
  );
}

// ============================================================ 玻璃核心

/// 玻璃的视觉层级
enum GlassRole {
  /// 卡片：最轻，细边框 + 一层薄斜面
  card,

  /// 控件：按钮、输入框，斜面更明显，带按压反馈
  control,

  /// 悬浮层：弹窗、面板，投影更重
  floating,
}

class _GlassLayers {
  const _GlassLayers({
    required this.fill,
    required this.onFill,
    required this.shadow,
  });

  final Color fill;
  final Color onFill;
  final Color shadow;

  /// 玻璃/卡片的填色。
  ///
  /// **这里是 iOS 化和 Material You 最本质的分界。**
  ///
  /// - M3：无边框，用 `surfaceContainerLow/High` 的**明度差**分层，
  ///   而且这些色调是由种子色推导的 —— 换个主题色，卡片底色偏紫偏绿。
  /// - iOS：**一套固定的语义色**。浅色下页面是浅灰（#F2F2F7），
  ///   卡片是**纯白**（#FFFFFF）；深色下页面纯黑，卡片是 #1C1C1E。
  ///   层次来自"灰底托白卡"这个对比，不来自明度阶梯。
  ///
  /// 所以这里整个换成 [AppSurface] 的固定色，只有强调色跟种子走。
  static _GlassLayers of(BuildContext context, GlassRole role) {
    final AppSurface s = AppSurface.of(context);
    final bool dark = s.isDark;

    final Color fill = switch (role) {
      // 卡片：iOS 的卡片是**纯白**（浅色）/ 二级灰（深色），
      // 压在浅灰页面底上 —— 对比清清楚楚。
      GlassRole.card => s.surface,
      // 控件：按钮、输入框。iOS 的次要按钮是"浅灰填充 + 无边框"，
      // 用的正是 codeBg 那一档灰（#F2F2F7 / #2C2C2E）。
      GlassRole.control => s.codeBg,
      // 悬浮层：面板拖到页面上，仍用卡片白，靠投影浮起来。
      GlassRole.floating => s.surface,
    };

    return _GlassLayers(
      fill: fill,
      onFill: s.text,
      // iOS 的分组卡片**几乎没有投影** —— 白卡压在灰底上已经足够分层了。
      // 再叠投影会显得脏，也偏离 iOS 那种"平"的观感。
      // 只有悬浮层（面板/弹窗）才给一层像样的投影。
      shadow: dark
          ? Colors.black
              .withValues(alpha: role == GlassRole.floating ? 0.55 : 0.0)
          : const Color(0xFF000000).withValues(
              alpha: role == GlassRole.floating ? 0.18 : 0.0,
            ),
    );
  }
}

/// 玻璃容器的实现核心。所有玻璃组件都走它，保证层次完全一致 ——
/// 否则迟早出现「按钮边框比卡片亮一点」这种细碎的不一致。
class _GlassBox extends StatelessWidget {
  const _GlassBox({
    required this.child,
    required this.radius,
    required this.role,
    this.padding = EdgeInsets.zero,
    this.tint,
    this.borderColor,
  });

  final Widget child;
  final double radius;
  final GlassRole role;
  final EdgeInsetsGeometry padding;
  final Color? tint;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final _GlassLayers g = _GlassLayers.of(context, role);

    // 半径很大时（999 = 想做成全圆角）**必须换成 StadiumBorder**。
    //
    // ContinuousRectangleBorder 用的是连续曲率（squircle）公式，
    // 半径超过短边一半时会算出畸形轮廓 —— 圆形图标按钮就是这样被压歪的。
    // StadiumBorder 在正方形上就是正圆，在长方形上是胶囊，正是想要的效果。
    final bool pill = radius >= 100;

    // 投影全为 0 时不要挂 BoxShadow —— 空 alpha 的 BoxShadow 仍会
    // 让 Flutter 走一遍阴影绘制路径（以及每个卡片一个 saveLayer），
    // 列表里几十张卡片就是白白的开销。
    final bool hasShadow = g.shadow.a > 0.001;

    // iOS 的卡片用**连续曲率**（squircle）而不是标准圆弧圆角 ——
    // 这是 iOS 观感里最不容易被说出来、但一眼能看出差别的一处。
    // 小半径（输入框、标签）用连续曲率反而会显得"没圆到位"，
    // 所以只在 >= 20 时启用。
    final ShapeBorder shape;
    if (pill) {
      shape = borderColor == null
          ? const StadiumBorder()
          : StadiumBorder(side: BorderSide(color: borderColor!, width: 1.1));
    } else if (radius >= 20) {
      shape = ContinuousRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: borderColor == null
            ? BorderSide.none
            : BorderSide(color: borderColor!, width: 1.1),
      );
    } else {
      shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: borderColor == null
            ? BorderSide.none
            : BorderSide(color: borderColor!, width: 1.1),
      );
    }

    final Widget content = Container(
      decoration: ShapeDecoration(
        shape: shape,
        color: tint ?? g.fill,
        shadows: hasShadow
            ? <BoxShadow>[
                BoxShadow(
                  color: g.shadow,
                  blurRadius: role == GlassRole.floating ? 30 : 10,
                  spreadRadius: role == GlassRole.floating ? -2 : 0,
                  offset: Offset(0, role == GlassRole.floating ? 10 : 2),
                ),
              ]
            : null,
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: g.onFill),
        child: Padding(padding: padding, child: child),
      ),
    );

    // 裁剪也用同一个 shape，保证描边和裁剪完全一致
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: content,
    );
  }
}

// ============================================================ 玻璃栏

/// 顶部 / 底部栏的玻璃。
///
/// 这是整个 app 里**真正会模糊内容**的地方 —— 消息从下面滚过时，
/// 顶部导航栏和底部输入栏会透出模糊。卡片在纯色背景上则靠厚度感区分。
class GlassBar extends StatelessWidget {
  const GlassBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    this.blur = 22,
    this.hairlineTop = false,
    this.hairlineBottom = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double blur;

  /// 在栏的顶部画一条发丝线（底栏用）
  final bool hairlineTop;

  /// 在栏的底部画一条发丝线（顶栏用）
  final bool hairlineBottom;

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);
    const double w = 0.7;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: s.barBackground,
            border: Border(
              top: hairlineTop
                  ? BorderSide(color: s.border, width: w)
                  : BorderSide.none,
              bottom: hairlineBottom
                  ? BorderSide(color: s.border, width: w)
                  : BorderSide.none,
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

// ============================================================ 玻璃卡片

/// 玻璃卡片。页面底色上的主要容器。
///
/// iOS 分组列表的卡片圆角是 10，独立卡片稍大。默认取 [AppRadius.card]（16）——
/// 之前是 30，那是 M3 那种"大圆角夸张化"的量级，iOS 上几乎看不到这么圆的卡片。
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.radius = AppRadius.card,
    this.color,
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget box = _GlassBox(
      radius: radius,
      role: GlassRole.card,
      tint: color,
      borderColor: borderColor,
      padding: padding,
      child: child,
    );

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: onTap == null
          ? box
          : Pressable(
              onTap: onTap,
              child: box,
            ),
    );
  }
}

// ============================================================ 玻璃按钮

/// 带按压反馈的玻璃胶囊按钮。
///
/// 按下时会轻微缩小并压暗 —— 这点反馈在纯色背景上尤其重要：
/// 没有它，玻璃按钮"按下去没反应"，手感很死。
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.accent = false,
    this.danger = false,
    this.expand = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
    this.fontSize = 14.5,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool accent;
  final bool danger;
  final bool expand;
  final EdgeInsetsGeometry padding;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);

    // **底色交给玻璃，强调色/危险色改由文字和图标承担。**
    //
    // 原来是三档实心底色（蓝 / 红 / 浅灰）。换成真正的液态玻璃之后，
    // `liquid_glass_widgets` 的按钮**没有对外暴露着色参数**（LiquidGlassSettings
    // 里没有 tint），所以做不到"蓝色玻璃按钮"。与其自己叠一层色块把玻璃盖住
    // （那就不是玻璃了），不如把语义交给前景色 —— 这也正是 iOS 26 工具栏按钮
    // 的做法：一块玻璃 + 着色图标/文字。
    //
    // 主次关系仍然清楚：主操作是 prominent（更厚、更不透明），
    // 次要操作是 filled（更薄、更透）。
    final Color fg = accent
        ? AppColors.accent
        : danger
            ? AppColors.danger
            : s.text;

    final Widget content = Padding(
      padding: padding,
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: fontSize + 3, color: fg),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppFonts.body(
                size: fontSize,
                // iOS 按钮文字是 semibold 而不是 bold —— 更细更"轻"。
                weight: FontWeight.w600,
                color: fg,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );

    return lg.GlassButton.custom(
      onTap: onTap ?? () {},
      enabled: onTap != null,
      // 用 `.custom` 这个命名构造，而不是默认那个。
      //
      // 默认构造是**给方形图标按钮**用的：`icon` 必填、`width/height` 默认 56、
      // 而且**根本没有 `child` 参数**（`child` 在默认构造里被写死成 null）。
      // `.custom` 才是给"文字/复合内容"用的，它的 width/height 默认就是 null，
      // 于是按钮按内容自适应 —— 这正是文字按钮需要的。
      width: expand ? double.infinity : null,
      // ---- 形状：用**具体数值**，不要用哨兵常量 ----
      //
      // 这个包的 `shape` 默认值是 `LiquidOval()`，等价于 Flutter 的
      // `OvalBorder` —— **真正的椭圆**，宽大于高的文字按钮会变成两头尖的。
      // 所以必须显式给形状。
      //
      // 但**不要**用 `GlassDefaults.capsuleRadius`（9999）这个哨兵值：
      // 包里只有 `GlassSegmentedControl` 和 `GlassTabBar` 会对它做特判
      // （文档原话是"检测到这个值后直接透传给 shader、不做内缩减法"）。
      // `GlassButton` 里**一处都没引用** capsuleRadius / effectiveRadius /
      // safeBorderRadius —— 它把这个半径原样送进 shader 的 SDF uniform，
      // 一个 9999 的半径会算出退化/畸变的轮廓。
      //
      // 23 对现在所有按钮都是胶囊（按钮高度 29~46，Flutter 会把半径夹到
      // 半高，正好等于 23 或更小），但 shader 拿到的是个正常数字。
      //
      // 分段控件那边用哨兵值是**对的** —— 它确实有那个特判。
      shape: const lg.LiquidRoundedRectangle(
        borderRadius: AppRadius.input,
      ),
      // **一律用 `filled`，不用 `prominent`。**
      //
      // 包对 `prominent` 的定义是"更厚的玻璃 + 更低的透明度，让按钮更重"——
      // 翻成视觉就是**更白的一块**。在深色底上，一个 prominent 玻璃按钮
      // 就是一块发光的白坨，"很多控件发白"里有它一份。
      //
      // 而强调色本来就不该由玻璃底承担：这个包**没有对外暴露玻璃着色参数**，
      // 所以主次只能靠图标和文字颜色表达 —— 这也正是 iOS 26 工具栏的做法：
      // 一块玻璃 + 着色图标/文字。用 `prominent` 想加强主次，付出的代价是
      // 整块变白，得不偿失。
      style: lg.GlassButtonStyle.filled,
      child: content,
    );
  }
}

/// 圆形玻璃图标按钮（液态玻璃）
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 40,
    this.iconSize = 19,
    this.tooltip,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);
    final bool disabled = onTap == null;

    // 注意 `Icon` **显式给了 color 和 size**：
    // 包的按钮默认从 `IconTheme` 取颜色（CupertinoColors.label）和尺寸，
    // 而这里的 color 承载了语义（危险操作是红的、禁用是灰的），
    // 必须由我们说了算，不能被主题盖掉。
    Widget button = lg.GlassIconButton(
      icon: Icon(icon, size: iconSize, color: color ?? s.text),
      // 包的这个按钮**没有 enabled 参数**（只有 GlassButton 有）。
      // 禁用态只能自己表现：给一个空回调 + 降透明度，
      // 而不是不传回调 —— 那会变成一个"点了没反应但看着是活的"按钮。
      onPressed: disabled ? () {} : onTap!,
      size: size,
      iconSize: iconSize,
      semanticLabel: tooltip,
    );

    if (disabled) {
      button = Opacity(opacity: 0.4, child: button);
    }

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// 按压反馈：缩小 + 压暗。
///
/// **为什么公开：** 这个应用关掉了 Material 的水波纹（见 `AppTheme` 的
/// `splashFactory`），因为水波纹是 Material 最强的视觉签名之一。
/// 代价是任何"自己包一层 GestureDetector"的地方都**完全没有按下反馈**，
/// 手感是死的。所以凡是需要可点区域、又不想引入 Material 组件的地方，
/// 都应该用这个包一层 —— 比如对话页顶部那个「点开历史记录」的标题。
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
  });

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _down ? 0.82 : 1.0,
          duration: const Duration(milliseconds: 90),
          child: widget.child,
        ),
      ),
    );
  }
}

// ============================================================ 小标签

/// 玻璃小标签（工具名、状态、风险等级）
class GlassChip extends StatelessWidget {
  const GlassChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.background,
    this.dense = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final Color? background;
  final bool dense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);

    // 传了 color（风险等级、状态标签）时，底色必须是**该颜色的低透明度版本**。
    // 之前一律用 secondaryContainer，会出现「绿色标签配紫色底」这种错配 ——
    // 语义色和容器色打架，看起来就是"按钮有问题"。
    //
    // 没传 color 时用 iOS 的中性灰填充（而不是 M3 的 secondaryContainer，
    // 那是个由种子色推导的色块，一眼就是 Material）。
    //
    // 用局部变量是因为：实例字段不会参与类型提升，`color.withValues` 会被
    // 判为"可能为 null"。局部变量可以提升。
    final Color? tintColor = color;
    final Color fg = tintColor ?? AppColors.accent;
    final Color bgFill = background ??
        (tintColor != null
            ? tintColor.withValues(alpha: s.isDark ? 0.26 : 0.15)
            : s.codeBg);

    final Widget chip = Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3.5 : 5,
      ),
      decoration: ShapeDecoration(
        color: bgFill,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: dense ? 11 : 12.5, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppFonts.body(
              size: dense ? 11 : 12,
              weight: FontWeight.w600,
              color: fg,
              height: 1.2,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return chip;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: chip,
    );
  }
}

/// 状态小圆点。用颜色表达状态，含义靠 tooltip / 点击提示补充。
class StatusDot extends StatelessWidget {
  const StatusDot({
    super.key,
    required this.color,
    this.size = 9,
    this.glow = false,
    this.onTap,
    this.tooltip,
  });

  final Color color;
  final double size;
  final bool glow;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final Widget dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: glow
            ? <BoxShadow>[
                BoxShadow(
                  color: color.withValues(alpha: 0.55),
                  blurRadius: 7,
                  spreadRadius: 1.2,
                ),
              ]
            : null,
      ),
    );

    // 视觉上只有一个小点，但触摸区要够大，否则点不中
    Widget tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Center(child: dot),
      ),
    );

    if (tooltip != null) {
      tappable = Tooltip(message: tooltip!, child: tappable);
    }
    return tappable;
  }
}
