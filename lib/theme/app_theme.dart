import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 字体常量。
///
/// 混排策略：把英文设为 [latin]（Times New Roman），并把 [cjk]（宋体 SimSun）放进
/// `fontFamilyFallback`。Flutter 是**逐字符**回退的——英文字符在 Times 里有字形，
/// 直接命中 Times；中文字符在 Times 里没有字形，于是落到宋体。这正好实现
/// 「英文 Times New Roman、中文宋体」的混排，不需要手工切分字符串。
class AppFonts {
  const AppFonts._();

  static const String latin = 'TimesNewRoman';
  static const String cjk = 'SimSun';
  static const String mono = 'Consolas';

  /// 全局字号缩放系数。
  ///
  /// 想整体调大/调小字号**只改这一个数**：所有文字都经过 [body] / [code]
  /// 产出，在这里乘一次就全覆盖了。
  ///
  /// 为什么不用 `MediaQuery.textScaler`：markdown 渲染走的是 `RichText`，
  /// 它**不会**响应 textScaler，结果是正文放大了、代码块和表格没放大，
  /// 排版反而更乱。在这里统一乘就没这个问题。
  static const double scale = 1.15;

  /// Times 没有中文字形，由宋体兜底；最后再兜一层系统 serif。
  static const List<String> bodyFallback = <String>[cjk, 'serif'];

  /// 代码样式：Consolas 打头，兜底等宽。刻意**不**回退到宋体，
  /// 否则代码里出现中文注释时字体会突然跳变成宋体，很难看。
  static const List<String> monoFallback = <String>[mono, 'monospace'];

  /// 正文 TextStyle 的统一构造：英文 Times、中文宋体。
  static TextStyle body({
    double size = 15,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double height = 1.6,
    double letterSpacing = 0.1,
  }) {
    return TextStyle(
      fontFamily: latin,
      fontFamilyFallback: bodyFallback,
      fontSize: size * scale,
      fontWeight: weight,
      height: height,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  /// 代码块样式：Consolas。
  static TextStyle code({
    double size = 13,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double height = 1.6,
  }) {
    return TextStyle(
      fontFamily: mono,
      fontFamilyFallback: monoFallback,
      fontSize: size * scale,
      fontWeight: weight,
      height: height,
      color: color,
      letterSpacing: 0,
    );
  }
}

/// 全局取色。背景是**纯白 / 纯黑**，卡片用极简的浅灰 / 深灰面，
/// 蓝色（accent）只出现在用户气泡和主按钮上。
class AppColors {
  const AppColors._();

  static const Color lightBg = Color(0xFFFFFFFF);
  static const Color darkBg = Color(0xFF000000);

  static const Color accent = Color(0xFF4F7DF3);
  static const Color danger = Color(0xFFFF453A);
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9F0A);

  /// 中性色：用于「无 Shizuku」这类「不是错误、只是缺失」的状态，
  /// 避免用红色吓唬用户以为应用坏了。
  static const Color neutral = Color(0xFF8A8A92);
}

/// 通过 ThemeExtension 下发「面 / 描边 / 代码底 / 次要文字」四组颜色，
/// 这样组件不必到处写 `isDark ? a : b`。
@immutable
class AppSurface extends ThemeExtension<AppSurface> {
  const AppSurface({
    required this.surface,
    required this.border,
    required this.codeBg,
    required this.text,
    required this.muted,
    required this.barBackground,
    required this.scrim,
  });

  /// 卡片底色
  final Color surface;

  /// 卡片描边（发丝线）
  final Color border;

  /// 代码块底色
  final Color codeBg;

  final Color text;
  final Color muted;

  /// 导航栏 / 输入栏的玻璃底色（半透明，配合 BackdropFilter）
  final Color barBackground;

  /// 弹窗后面的遮罩
  final Color scrim;

  static const AppSurface light = AppSurface(
    surface: Color(0xFFF7F7F9),
    border: Color(0xFFEDEDF0),
    codeBg: Color(0xFFEFEFF2),
    text: Color(0xFF0A0A0C),
    muted: Color(0xFF82868F),
    barBackground: Color(0xB8FFFFFF), // 72% 白
    scrim: Color(0x57000000),
  );

  static const AppSurface dark = AppSurface(
    surface: Color(0xFF0D0D10),
    border: Color(0xFF1E1E23),
    codeBg: Color(0xFF08080A),
    text: Color(0xFFEDEDF1),
    muted: Color(0xFF8A8A92),
    barBackground: Color(0xB30A0A0C), // 70% 近黑
    scrim: Color(0x8A000000),
  );

  static AppSurface of(BuildContext context) {
    return Theme.of(context).extension<AppSurface>() ??
        (Theme.of(context).brightness == Brightness.dark ? dark : light);
  }

  @override
  AppSurface copyWith({
    Color? surface,
    Color? border,
    Color? codeBg,
    Color? text,
    Color? muted,
    Color? barBackground,
    Color? scrim,
  }) {
    return AppSurface(
      surface: surface ?? this.surface,
      border: border ?? this.border,
      codeBg: codeBg ?? this.codeBg,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      barBackground: barBackground ?? this.barBackground,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  AppSurface lerp(ThemeExtension<AppSurface>? other, double t) {
    if (other is! AppSurface) return this;
    return AppSurface(
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      codeBg: Color.lerp(codeBg, other.codeBg, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      barBackground: Color.lerp(barBackground, other.barBackground, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

/// 全局主题。暗色模式通过 [ThemeMode.system] 跟随系统。
class AppTheme {
  const AppTheme._();

  /// 沉浸式系统栏（亮色）：透明状态栏/导航栏 + 深色图标。
  ///
  /// 两个 `*ContrastEnforced: false` 很关键：Android 10+ 默认会给
  /// 透明导航栏自动加一层半透明遮罩，导致纯黑背景底部发灰、破坏沉浸感。
  static const SystemUiOverlayStyle lightSystemUi = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark, // Android：浅底用深色图标
    statusBarBrightness: Brightness.light, // iOS
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarContrastEnforced: false,
  );

  /// 沉浸式系统栏（暗色）：透明 + 浅色图标。
  /// 不设这个的话，深色模式下状态栏图标是深色的，压在纯黑背景上几乎看不见。
  static const SystemUiOverlayStyle darkSystemUi = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarContrastEnforced: false,
  );

  static SystemUiOverlayStyle systemUiFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkSystemUi : lightSystemUi;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final AppSurface surface = isDark ? AppSurface.dark : AppSurface.light;

    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: brightness,
    ).copyWith(surface: isDark ? AppColors.darkBg : AppColors.lightBg);

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );

    // 关键：一次性把 Times + 宋体 fallback 应用到整套 textTheme，
    // 这样所有组件（含 Dialog / SnackBar / 按钮）都自动获得正确字体。
    final TextTheme textTheme = base.textTheme.apply(
      fontFamily: AppFonts.latin,
      fontFamilyFallback: AppFonts.bodyFallback,
      bodyColor: surface.text,
      displayColor: surface.text,
    );

    return base.copyWith(
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[surface],
      scaffoldBackgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      canvasColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: surface.text,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xF2121216) : const Color(0xF2FFFFFF),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: surface.border),
        ),
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: surface.text,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: surface.text),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xF21A1A1E) : const Color(0xF2FFFFFF),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: surface.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: surface.border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? const Color(0xFF0D0D10) : const Color(0xFFFFFFFF),
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: surface.border,
        thickness: 0.7,
        space: 0.7,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: surface.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: surface.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: surface.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.2),
        ),
        hintStyle: AppFonts.body(size: 14.5, color: surface.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.accent,
        selectionColor: AppColors.accent.withValues(alpha: 0.28),
        selectionHandleColor: AppColors.accent,
      ),
      listTileTheme: ListTileThemeData(
        textColor: surface.text,
        iconColor: surface.text,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
      ),
      // 统一开关样式。用 WidgetStateProperty 而不是已废弃的 activeColor。
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? Colors.white
              : (isDark ? const Color(0xFF8A8A92) : const Color(0xFFFFFFFF)),
        ),
        trackColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? AppColors.accent
              : (isDark ? const Color(0xFF26262C) : const Color(0xFFE4E4E8)),
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : surface.border,
        ),
      ),
    );
  }
}
