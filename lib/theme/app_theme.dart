import 'package:flutter/cupertino.dart' show CupertinoTextThemeData, CupertinoThemeData;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/custom_font.dart';

/// 字体常量。
///
/// 混排策略：把英文设为 [latin]（Times New Roman），并把 [cjk]（宋体 SimSun）放进
/// `fontFamilyFallback`。Flutter 是**逐字符**回退的——英文字符在 Times 里有字形，
/// 直接命中 Times；中文字符在 Times 里没有字形，于是落到宋体。这正好实现
/// 「英文 Times New Roman、中文宋体」的混排，不需要手工切分字符串。
class AppFonts {
  const AppFonts._();

  // ---- 字体方案（可在设置里切换，所以不是 const）----

  /// 正文字体族
  static String latin = 'TimesNewRoman';

  /// 中文兜底族
  static String cjk = 'SimSun';

  /// 等宽字体族
  static String mono = 'Consolas';

  /// 用户额外放大的倍数（设置里的滑杆）
  static double userScale = 1.0;

  /// 基础缩放 —— 这是"整体字号"的基准值。
  /// 最终倍率 = [baseScale] × [userScale]。
  ///
  /// 为什么不用 `MediaQuery.textScaler`：markdown 渲染走的是 `RichText`，
  /// 它**不会**响应 textScaler，结果是正文放大了、代码块和表格没放大，
  /// 排版反而更乱。在字体工厂里乘一次就没这个问题。
  ///
  /// 为什么是 1.0：这里曾经是 1.15，等于给所有字号悄悄加了 15%，
  /// 结果是正文 17.25px、标题 28.75px —— 比 iOS 自己的规格还大一档，
  /// 整屏看起来"字很大、很挤"。1.0 意味着**调用点写的数字就是实际像素**，
  /// 不用在心里做一次换算。想让字大一点是设置里那根滑杆的事。
  static const double baseScale = 1.0;

  /// 最终倍率
  static double get scale => baseScale * userScale;

  /// 正文回退链
  static List<String> bodyFallback = <String>[cjk, 'serif'];

  /// 代码回退链。刻意**不**回退到宋体 ——
  /// 否则代码里的中文注释会突然跳成宋体，很难看。
  static List<String> monoFallback = <String>['Consolas', 'monospace'];

  /// 可选的字体方案。
  ///
  /// 三个都**不依赖额外字体文件**：
  /// 前两个用已打包的 Times/宋体，第三个用 Android 系统自带的
  /// `sans-serif` / `monospace` 族名（Flutter 会映射到系统字体，
  /// 不需要在 pubspec 里声明）。
  /// 所以换方案**不增加 APK 体积**。
  static const List<(String, String, String)> schemes = <(String, String, String)>[
    ('pingfang', '苹方 PingFang', '苹果的中文黑体，中英文都用它'),
    ('sans', '系统无衬线（iOS 风）', 'SF / Roboto 观感，界面更紧凑'),
    ('serif', '衬线（Times + 宋体）', '适合长文阅读，偏阅读器气质'),
    ('mono', '等宽', '适合看代码和数据'),
    ('custom', '自定义字体文件', '选任意 .ttf / .otf / .ttc'),
  ];

  /// 应用某个字体方案。由主题构建时调用。
  ///
  /// ### 回退链里**必须**有一个带中文字形的字体
  ///
  /// 等宽字体（Consolas、monospace）基本都**没有中文字形**。只写
  /// `['Consolas', 'monospace']` 的话，代码块里的中文注释、或者用
  /// `AppFonts.code()` 渲染的中文标签，会直接渲染成**空心方块**。
  ///
  /// 这个坑很隐蔽：代码块平时都是 ASCII，看不出问题；
  /// 直到某个中文出现在 code 字体里才突然全是豆腐块。
  ///
  /// 所以每条 mono 链的最后都挂上该方案的 CJK 族兜底。
  /// （旧代码刻意不回退到宋体，理由是"代码里的中文跳成宋体很难看" ——
  /// 但**豆腐块比难看的字体糟糕得多**，两害相权取其轻。）
  static void applyScheme(String scheme) {
    switch (scheme) {
      case 'pingfang':
        // 苹方：中英文都走它，不做混排回退。
        //
        // 苹方自带完整的西文字形（而且西文部分是按苹果的比例设计的），
        // 硬要"英文走 Times、中文走苹方"反而会出现两种字体的割裂感。
        //
        // 兜底链留 'sans-serif'：万一某个生僻字苹方没有，还能落到系统字体，
        // 不至于显示成方块。
        latin = 'PingFang';
        cjk = 'PingFang';
        bodyFallback = <String>['sans-serif'];
        mono = 'monospace';
        monoFallback = <String>['monospace', 'PingFang', 'sans-serif'];
        break;

      case 'serif':
        latin = 'TimesNewRoman';
        cjk = 'SimSun';
        bodyFallback = <String>['SimSun', 'serif'];
        mono = 'Consolas';
        monoFallback = <String>['Consolas', 'monospace', 'SimSun', 'serif'];
        break;

      case 'mono':
        latin = 'monospace';
        cjk = 'monospace';
        bodyFallback = <String>['monospace', 'sans-serif'];
        mono = 'Consolas';
        monoFallback = <String>['Consolas', 'monospace', 'sans-serif'];
        break;

      case 'custom':
        // 用户自己加载的字体文件（苹方等）。见 core/custom_font.dart。
        //
        // 中文和英文**都**走它，不做混排回退 —— 苹方、思源这类字体本来就
        // 自带完整的西文字形，硬要混排反而会出现"英文一种、中文另一种"的
        // 割裂感。真缺字形时 Flutter 会自己落到系统默认，不会显示方块。
        //
        // 没加载字体文件时这个家族名不存在，Flutter 会一路回退到系统默认 ——
        // **不会崩**，只是没效果。设置里那行会显示"未选择"来告诉用户原因。
        latin = CustomFont.family;
        cjk = CustomFont.family;
        bodyFallback = <String>['sans-serif'];
        mono = 'monospace';
        monoFallback = <String>['monospace', 'sans-serif'];
        break;

      case 'sans':
      default:
        // iOS 风格就是无衬线。用系统族名（`sans-serif`），
        // Flutter 会映射到设备的默认无衬线字体（Android 上是 Roboto），
        // **不需要在 pubspec 里声明额外字体文件**。
        //
        // 注意：中文在 Android 上会落到系统的 Noto Sans CJK ——
        // 观感和苹方接近，所以不想多带 11MB 字体的人用这个方案就够了。
        latin = 'sans-serif';
        cjk = 'sans-serif';
        bodyFallback = <String>['sans-serif'];
        mono = 'monospace';
        monoFallback = <String>['monospace', 'sans-serif'];
        break;
    }
  }

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

  /// 页面底色。
  ///
  /// **iOS 化最关键的一处改动**：浅色下从纯白改成浅灰（iOS 的
  /// `systemGroupedBackground`）。整个"灰底浮着白卡"的观感就来自它 ——
  /// 纯白底上再放白卡，层次全靠描边撑，那是 Material 的做法。
  ///
  /// 改这一个值会传播到全项目 26 处引用，所以不需要逐页去改。
  static const Color lightBg = iosBgLight;
  static const Color darkBg = iosBgDark;

  /// 强调色。**固定为 iOS 系统蓝**。
  ///
  /// 这里原本是"用户在设置里选一个种子色，整个应用跟着变"（Material You 的
  /// 核心玩法）。那个功能已经删掉了，理由：
  ///
  /// · 它在概念上属于 Material You —— 换种子色时连表面色都会跟着推导出来。
  ///   而这个应用的骨架已经是 iOS 的**固定语义色**（灰底白卡），种子色
  ///   只能改到强调色一处，剩下半套 Material You 反而自相矛盾。
  /// · 现在界面走的是液态玻璃。玻璃的观感靠的是**折射和边缘高光**，
  ///   强调色变来变去只会让玻璃上的着光显得脏。
  ///
  /// 为什么仍然保留一个静态字段、而不是让调用方读 `Theme.of(context)`：
  /// 全项目有几十处直接引用 `AppColors.accent`，改成 context 查找要动很多文件，
  /// 还有在 build 之外（回调、异步逻辑里）拿不到 context 的风险。
  /// 现在是编译期常量，反而是最省事也最不会出错的形式。
  static const Color accent = defaultSeed;

  /// 强调色的具体取值 —— iOS 系统蓝。
  static const Color defaultSeed = Color(0xFF007AFF);

  // ---------------------------------------------------------- iOS 系统色
  //
  // iOS 的观感很大程度上来自这套**固定的语义色**，而不是从种子色推导出的
  // 一整套色板。所以这里直接写死，只让强调色跟着种子走。

  /// 分组背景（页面底）：浅灰 / 纯黑
  static const Color iosBgLight = Color(0xFFF2F2F7);
  static const Color iosBgDark = Color(0xFF000000);

  /// 卡片 / 分组：white / 二级背景
  static const Color iosCardLight = Color(0xFFFFFFFF);
  static const Color iosCardDark = Color(0xFF1C1C1E);

  /// 更下一层（代码块、输入框）
  static const Color iosCard2Light = Color(0xFFF2F2F7);
  static const Color iosCard2Dark = Color(0xFF2C2C2E);

  /// 分隔线（发丝线）
  static const Color iosSepLight = Color(0xFFC6C6C8);
  static const Color iosSepDark = Color(0xFF38383A);

  /// 主文字 / 次要文字
  static const Color iosLabelLight = Color(0xFF000000);
  static const Color iosLabelDark = Color(0xFFFFFFFF);
  static const Color iosMuted = Color(0xFF8E8E93);

  static const Color danger = Color(0xFFFF3B30);
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9500);

  /// 中性色：用于「无 Shizuku」这类「不是错误、只是缺失」的状态，
  /// 避免用红色吓唬用户以为应用坏了。
  static const Color neutral = Color(0xFF8E8E93);
}

/// 圆角刻度。
///
/// 之前全项目散落着 9/10/11/12/14/16/23/24 八种半径，同一屏里相邻两个
/// 元素常常只差 1–2px —— 说不出哪里不对，但看着就是"膈应"。
/// 统一成一套刻度就消除了这种噪声：**要么明显不同，要么完全一致**，
/// 不要"差不多但不一样"。
class AppRadius {
  const AppRadius._();

  /// 代码块、小色块
  static const double code = 10;

  /// 输入框、列表项、小卡片
  static const double field = 12;

  /// 普通卡片（iOS 分组列表内嵌圆角是 10，卡片类稍大一点更耐看）
  static const double card = 16;

  /// 弹窗、面板的顶部圆角
  static const double sheet = 20;

  /// 聊天输入框的圆角 —— **胶囊**。
  ///
  /// 这个值不是随便取的：它必须等于两侧圆形按钮的半径。
  /// 那一行三个控件的高度都是 46，圆形按钮的半径就是 46 ÷ 2 = 23；
  /// 输入框如果用一个"差不多圆"的值（比如卡片圆角 16），
  /// 就会出现「圆按钮 + 方框」并排 —— 说不出哪里不对，但就是没对齐。
  ///
  /// 嵌套圆角的通用规矩是一样的：**内半径 = 外半径 − 内缩量**，
  /// 或者干脆做成同一族的胶囊/正圆。半吊子的圆角最难看。
  static const double input = 23;

  /// 全圆角（胶囊按钮、圆形图标按钮）
  static const double pill = 999;
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
    required this.isDark,
  });

  /// 是否暗色。
  ///
  /// **必须用这个字段判断明暗，不要再写 `s == AppSurface.dark`。**
  /// 那是个陷阱：颜色现在由种子色推导（`fromScheme` 返回新实例），
  /// 而 `AppSurface.dark` 是静态常量 —— 两者永远不相等，
  /// 判断会恒为 false，暗色模式就整片变白。
  final bool isDark;

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

  /// 亮色默认面（iOS 分组样式：浅灰底 + 白卡）。
  static const AppSurface light = AppSurface(
    surface: AppColors.iosCardLight,
    border: Color(0x99C6C6C8), // iosSep 60%
    codeBg: AppColors.iosCard2Light,
    text: AppColors.iosLabelLight,
    muted: AppColors.iosMuted,
    barBackground: Color(0xC7F9F9F9), // 78% 白
    scrim: Color(0x66000000),
    isDark: false,
  );

  /// 暗色默认面（iOS：纯黑底 + 二级灰卡）。
  static const AppSurface dark = AppSurface(
    surface: AppColors.iosCardDark,
    border: AppColors.iosSepDark,
    codeBg: AppColors.iosCard2Dark,
    text: AppColors.iosLabelDark,
    muted: AppColors.iosMuted,
    barBackground: Color(0xB81C1C1E), // 72% 二级背景
    scrim: Color(0x99000000),
    isDark: true,
  );

  /// 从配色方案推导「面 / 描边 / 代码底 / 次要文字」。
  ///
  /// **这里是 iOS 化和 Material You 的分界点。**
  ///
  /// M3 的做法是表面色也由种子推导（`surfaceContainerLow` 之类），
  /// 于是换主题色时卡片底色跟着变。iOS 不是这样 —— 它有**一套固定的
  /// 语义色**（灰底 + 白卡），观感正来自那份固定。
  ///
  /// 所以这里改成：**只有强调色跟种子走，面/底/线/字全部用 iOS 系统色**。
  /// 换主题色时按钮和强调元素变色，但页面骨架保持 iOS 的样子。
  factory AppSurface.fromScheme(ColorScheme s, {required bool dark}) {
    if (dark) {
      return AppSurface(
        surface: AppColors.iosCardDark,
        border: AppColors.iosSepDark,
        codeBg: AppColors.iosCard2Dark,
        text: AppColors.iosLabelDark,
        muted: AppColors.iosMuted,
        // 栏底色必须**足够透**，否则 BackdropFilter 的模糊被盖住看不见。
        // iOS 的大标题栏本来就是半透明 + 模糊，这里保留这个特性。
        barBackground: const Color(0xFF1C1C1E).withValues(alpha: 0.72),
        scrim: Colors.black.withValues(alpha: 0.60),
        isDark: true,
      );
    }
    return AppSurface(
      surface: AppColors.iosCardLight,
      border: AppColors.iosSepLight.withValues(alpha: 0.6),
      codeBg: AppColors.iosCard2Light,
      text: AppColors.iosLabelLight,
      muted: AppColors.iosMuted,
      barBackground: const Color(0xFFF9F9F9).withValues(alpha: 0.78),
      scrim: Colors.black.withValues(alpha: 0.40),
      isDark: false,
    );
  }

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
    bool? isDark,
  }) {
    return AppSurface(
      surface: surface ?? this.surface,
      border: border ?? this.border,
      codeBg: codeBg ?? this.codeBg,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      barBackground: barBackground ?? this.barBackground,
      scrim: scrim ?? this.scrim,
      isDark: isDark ?? this.isDark,
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
      isDark: t < 0.5 ? isDark : other.isDark,
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

    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.defaultSeed,
      brightness: brightness,
    ).copyWith(
      // 强调色直接用 `#007AFF` 本身，不要 M3 从种子里映射出来的那一档。
      //
      // M3 的 `fromSeed` 会把种子色映射到一条色调曲线上的某个 tone，结果
      // `#007AFF` 得到的 `primary` 并不是 `#007AFF`。而 iOS 的 tint color
      // 就是那个颜色本身。
      //
      // 更要紧的是**一致性**：按钮/标签走的是 `AppColors.accent`，
      // 而 Slider、Checkbox、Radio、输入框焦点环走的是 `colorScheme.primary`。
      // 不统一的话两者会有肉眼可辨的细微色差，而这种"说不清哪里不对"最难受。
      primary: AppColors.defaultSeed,
      // 页面底是分组灰（浅色）/ 纯黑（暗色）。
      surface: isDark ? AppColors.darkBg : AppColors.lightBg,
    );

    final AppSurface surface = AppSurface.fromScheme(scheme, dark: isDark);

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
      // 让**液态玻璃那些控件**也用同一套字体。
      //
      // liquid_glass_widgets 是 Material-free 的，它读的是 `CupertinoTheme`
      // 而不是 `ThemeData.textTheme`。不接这一根的话，它的文字（分段控件、
      // 玻璃按钮的标签…）会走 Cupertino 默认字体 —— 于是用户一选「衬线」
      // 或「自定义字体」，界面里就冒出几处字体不一样的地方，
      // 而且很难看出是哪里不对。
      //
      // `ThemeData.cupertinoOverrideTheme` 正是为这种"Material 应用里
      // 用 Cupertino 组件"的场景准备的。
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        textTheme: CupertinoTextThemeData(
          textStyle: AppFonts.body(size: 14, color: surface.text),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[surface],
      scaffoldBackgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      canvasColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      // iOS 没有 Material 的水波纹 —— 点击反馈是"按下变暗"（见 glass.dart 的
      // _Pressable）。保留 InkSparkle 的话，每个按钮按下都炸出一圈 Material
      // 味道很强的火花，iOS 观感立刻破功。
      splashFactory: NoSplash.splashFactory,
      // 但**不能**把高亮也一起关掉。
      //
      // 水波纹关掉之后，`InkWell` 就只剩高亮这一种反馈了；高亮也设成透明的话，
      // 那些走 Material + InkWell 的控件（比如输入栏右边的发送按钮）按下去
      // **完全没有反应**，手感是死的。
      //
      // iOS 本来就有"按下变暗"，所以给一层很淡的压暗正好 —— 既不是 Material
      // 的扩散动画，又有反馈。
      highlightColor: isDark
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.black.withValues(alpha: 0.08),
      splashColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: surface.text,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.iosCardDark : AppColors.iosCardLight,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: surface.text,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: surface.text),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xF21C1C1E) : const Color(0xF2FFFFFF),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: surface.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          side: BorderSide(color: surface.border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        // 面板底色用**分组灰**，不是白色。
        //
        // 这个应用里所有面板的内容都是「分组列表」——分组标题 + 一张张白卡。
        // iOS 在这种场景用的正是 `systemGroupedBackground`（浅灰），
        // 白卡压在灰底上才分层。如果面板底是白的，白卡就"沉"进背景里看不见了。
        //
        // （iOS 里纯白面板用于"动作面板/分享面板"那类内容，不是分组列表。）
        //
        // 面板圆角 + 底色在这里统一定义，各调用点**不要**再自己画一遍：
        // 之前每个面板都传 `backgroundColor: Colors.transparent` 然后自己
        // 铺一层 24 圆角的容器，结果主题的 20 圆角在四角露出一线白边。
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        surfaceTintColor: Colors.transparent,
        // 注意：**不开** `showDragHandle`。
        //
        // 项目里每个面板都已经自己画了把手（和标题同一个 Padding，视觉上是一组），
        // 再让主题画一根就会变成两根叠在一起。这里的取舍是保留各面板自己的 ——
        // 它们本来就是一致的（都是 38×4、颜色 s.border）。
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
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
        fillColor: surface.codeBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: AppColors.accent, width: 1.6),
        ),
        hintStyle: AppFonts.body(size: 14.5, color: surface.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.accent,
      ),
      // 统一开关样式。
      //
      // 打开时用 iOS 的**系统绿**而不是主题色：这是 iOS 上少数几个
      // 「不跟随 tint color」的控件之一，用户对它的绿色有肌肉记忆。
      // 换成蓝色反而会让人一愣。
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) =>
              states.contains(WidgetState.selected) ? Colors.white : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? AppColors.success
              : (isDark ? const Color(0xFF39393D) : const Color(0xFFE9E9EB)),
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => Colors.transparent,
        ),
      ),
    );
  }
}
