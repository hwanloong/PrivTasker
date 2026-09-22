import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// 顶部 / 底部栏的玻璃。
///
/// 这是整个 app 里**唯一真正使用玻璃**的地方：背景是纯白/纯黑，卡片是实心面，
/// 只有导航栏和输入栏用 [BackdropFilter]，让滚动上去的消息在栏下透出模糊。
/// 纯色背景上静态看它和背景同色——这是对的，玻璃只有在有内容穿过时才可见。
class GlassBar extends StatelessWidget {
  const GlassBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    this.blur = 20,
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

/// 实心卡片面（消息卡片、工具卡片、设置分组都用它）。
/// 纯白/纯黑背景上，靠极浅的底色 + 发丝描边来区分层次。
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.radius = 18,
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
    final AppSurface s = AppSurface.of(context);
    final BorderRadius br = BorderRadius.circular(radius);

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: color ?? s.surface,
        borderRadius: br,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: br,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: br,
              border: Border.all(color: borderColor ?? s.border, width: 0.8),
            ),
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 胶囊按钮
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

    final Color bg = accent
        ? AppColors.accent
        : danger
            ? AppColors.danger
            : s.surface;
    final Color fg = (accent || danger) ? Colors.white : s.text;
    final Color border = (accent || danger) ? Colors.transparent : s.border;

    return Opacity(
      opacity: onTap == null ? 0.45 : 1.0,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border, width: 0.9),
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
      ),
    );
  }
}

/// 圆形图标按钮
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
      child: Material(
        color: s.surface,
        shape: CircleBorder(side: BorderSide(color: s.border, width: 0.9)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
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

/// 状态小圆点。
///
/// 比文字标签省空间得多，适合放在标题右侧。
/// 用颜色表达状态（绿=就绪、橙=缺权限、灰=不可用），
/// 具体含义靠 tooltip / 点击提示来补充。
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

  /// 就绪状态加一圈柔光，让「活着」这件事一眼可见
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

/// 小标签（工具名、状态、风险等级）
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
    final Color fg = color ?? s.muted;

    final Widget chip = Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 9,
        vertical: dense ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: background ?? fg.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
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
