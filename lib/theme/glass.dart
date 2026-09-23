import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_theme.dart';

// ============================================================ 圆角：连续曲率

/// iOS 那种「连续曲率」圆角路径（俗称 squircle）。
///
/// Flutter 没有原生的 squircle，但 [ContinuousRectangleBorder] 的路径就是
/// 这个形状 —— 直接复用，不要手写超椭圆公式（很容易画歪）。
Path squirclePath(Rect rect, double radius) {
  return ContinuousRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
  ).getOuterPath(rect);
}

/// 用 squircle 裁剪。配合 [BackdropFilter] 或图片圆角用。
class SquircleClipper extends CustomClipper<Path> {
  const SquircleClipper(this.radius);

  final double radius;

  @override
  Path getClip(Size size) => squirclePath(Offset.zero & size, radius);

  @override
  bool shouldReclip(SquircleClipper oldClipper) =>
      oldClipper.radius != radius;
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

  /// Material You 的层次靠**色调容器**表达，不靠边框。
  ///
  /// 这是和 iOS 风格最本质的区别：
  /// - iOS：白底 + 发丝描边 + 投影
  /// - M3：无边框，用 `surfaceContainerLow/High/Highest` 的**明度差**分层
  ///
  /// 所以这里不再返回 border —— 卡片没有边框。
  static _GlassLayers of(BuildContext context, GlassRole role) {
    final ColorScheme c = Theme.of(context).colorScheme;
    final bool dark = c.brightness == Brightness.dark;

    final Color fill = switch (role) {
      // 卡片：最轻的一档，只比背景略深/略浅
      GlassRole.card => c.surfaceContainerLow,
      // 控件：按钮、输入框，比卡片再高一层
      GlassRole.control => c.surfaceContainerHigh,
      // 悬浮层：弹窗面板，最高
      GlassRole.floating => c.surfaceContainerHigh,
    };

    return _GlassLayers(
      fill: fill,
      onFill: c.onSurface,
      // M3 的投影很克制：elevation 1/2 级只有极淡一层
      shadow: dark
          ? Colors.black
              .withValues(alpha: role == GlassRole.floating ? 0.45 : 0.22)
          : const Color(0xFF101828).withValues(
              alpha: role == GlassRole.floating ? 0.10 : 0.03,
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

    // M3 的卡片**没有边框** —— 靠填色分层。只有在调用方显式给了
    // borderColor 时才画（比如"已选中"状态、危险操作）。
    final ShapeBorder shape = pill
        ? (borderColor == null
            ? const StadiumBorder()
            : StadiumBorder(
                side: BorderSide(color: borderColor!, width: 1.1)))
        : (borderColor == null
            ? ContinuousRectangleBorder(
                borderRadius: BorderRadius.circular(radius),
              )
            : ContinuousRectangleBorder(
                borderRadius: BorderRadius.circular(radius),
                side: BorderSide(color: borderColor!, width: 1.1),
              ));

    final Widget content = Container(
      decoration: ShapeDecoration(
        shape: shape,
        color: tint ?? g.fill,
        shadows: <BoxShadow>[
          BoxShadow(
            color: g.shadow,
            blurRadius: role == GlassRole.floating ? 24 : 8,
            spreadRadius: -4,
            offset: Offset(0, role == GlassRole.floating ? 8 : 2),
          ),
        ],
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

/// 玻璃卡片。纯白/纯黑背景上的主要容器。
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.radius = 30,
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
          : _Pressable(
              onTap: onTap,
              radius: radius,
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
    final ColorScheme c = Theme.of(context).colorScheme;

    // M3 按钮有三种色调角色，这里对应：
    //   accent  → Filled（primary 填充）      ：主操作
    //   danger  → Filled（error 填充）        ：破坏性操作
    //   默认    → FilledTonal（次要容器填充） ：普通操作
    // 不再用"白色叠透明度"—— 那样换主题色时按钮不会跟着变。
    final Color bg = accent
        ? c.primary
        : danger
            ? c.error
            : c.secondaryContainer;
    final Color fg = accent
        ? c.onPrimary
        : danger
            ? c.onError
            : c.onSecondaryContainer;

    return Opacity(
      opacity: onTap == null ? 0.45 : 1.0,
      child: _Pressable(
        onTap: onTap,
        radius: 999,
        child: Container(
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: bg,
          ),
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
                    weight: FontWeight.w600,
                    color: fg,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 圆形玻璃图标按钮
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

    final Widget button = Opacity(
      opacity: onTap == null ? 0.4 : 1.0,
      child: _Pressable(
        onTap: onTap,
        radius: 999,
        child: _GlassBox(
          radius: 999,
          role: GlassRole.control,
          padding: EdgeInsets.zero,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: Icon(icon, size: iconSize, color: color ?? s.text),
            ),
          ),
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// 按压反馈：缩小 + 压暗
class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.child,
    required this.radius,
    this.onTap,
  });

  final Widget child;
  final double radius;
  final VoidCallback? onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
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
    final ColorScheme c = Theme.of(context).colorScheme;

    // 传了 color（风险等级、状态标签）时，底色必须是**该颜色的低透明度版本**。
    // 之前一律用 secondaryContainer，会出现「绿色标签配紫色底」这种错配 ——
    // 语义色和容器色打架，看起来就是"按钮有问题"。
    //
    // 用局部变量是因为：实例字段不会参与类型提升，`color.withValues` 会被
    // 判为"可能为 null"。局部变量可以提升。
    final Color? tintColor = color;
    final bool dark = c.brightness == Brightness.dark;
    final Color fg = tintColor ?? c.onSecondaryContainer;
    final Color bgFill = background ??
        (tintColor != null
            ? tintColor.withValues(alpha: dark ? 0.24 : 0.14)
            : c.secondaryContainer);

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
