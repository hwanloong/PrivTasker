// Markdown 渲染预览：用一段「真实 AI 回复风格」的样本，
// 把各种语法一次性渲染出来，用于肉眼确认哪些支持、哪些漏了。
//
//   flutter test test/markdown_preview_test.dart --update-goldens
import 'dart:io';

import 'package:dsh_agent/theme/app_theme.dart';
import 'package:dsh_agent/ui/markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFonts() async {
  final Map<String, List<String>> families = <String, List<String>>{
    'TimesNewRoman': <String>['assets/fonts/times.ttf', 'assets/fonts/timesbd.ttf'],
    'SimSun': <String>['assets/fonts/simsun.ttf'],
    'Consolas': <String>['assets/fonts/consola.ttf'],
  };

  // 数学公式用的是包自带的 KaTeX 字体。测试环境必须显式加载，
  // 否则字形会渲染成实心方块 —— 和 Icon 需要加载 MaterialIcons 是同一回事。
  //
  // 注意：字体族名**带包名前缀**。包的 make_symbol.dart 里写的是
  //   fontFamily: 'packages/flutter_math_fork/KaTeX_$family'
  // 所以这里必须注册成 'packages/flutter_math_fork/KaTeX_Main'，
  // 注册成裸的 'KaTeX_Main' 匹配不上，会静默回退到占位字体。
  const String kp = 'packages/flutter_math_fork';
  const String k = '$kp/lib/katex_fonts/fonts';
  families.addAll(<String, List<String>>{
    '$kp/KaTeX_Main': <String>[
      '$k/KaTeX_Main-Regular.ttf',
      '$k/KaTeX_Main-Bold.ttf',
      '$k/KaTeX_Main-Italic.ttf',
      '$k/KaTeX_Main-BoldItalic.ttf',
    ],
    '$kp/KaTeX_Math': <String>[
      '$k/KaTeX_Math-Italic.ttf',
      '$k/KaTeX_Math-BoldItalic.ttf',
    ],
    '$kp/KaTeX_AMS': <String>['$k/KaTeX_AMS-Regular.ttf'],
    '$kp/KaTeX_Size1': <String>['$k/KaTeX_Size1-Regular.ttf'],
    '$kp/KaTeX_Size2': <String>['$k/KaTeX_Size2-Regular.ttf'],
    '$kp/KaTeX_Size3': <String>['$k/KaTeX_Size3-Regular.ttf'],
    '$kp/KaTeX_Size4': <String>['$k/KaTeX_Size4-Regular.ttf'],
    '$kp/KaTeX_Caligraphic': <String>['$k/KaTeX_Caligraphic-Regular.ttf'],
    '$kp/KaTeX_Script': <String>['$k/KaTeX_Script-Regular.ttf'],
    '$kp/KaTeX_Typewriter': <String>['$k/KaTeX_Typewriter-Regular.ttf'],
  });

  for (final MapEntry<String, List<String>> e in families.entries) {
    final FontLoader loader = FontLoader(e.key);
    for (final String a in e.value) {
      loader.addFont(rootBundle.load(a));
    }
    await loader.load();
  }

  final FontLoader iconLoader = FontLoader('MaterialIcons');
  iconLoader.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await iconLoader.load();
}

/// 贴近 DeepSeek 实际会输出的内容。
///
/// 用 raw string：样本里有 LaTeX 的 `\int`、`\frac` 和 `$`，
/// 普通字符串会把 `$E` 当成插值、把 `\i` 当成转义。
const String _sample = r'''
好的，我来帮你查一下。下面是结果。

## 电池信息

当前电量为 **73%**，状态是 *充电中*。相关命令是 `dumpsys battery`。

| 项目 | 值 | 说明 |
|------|-----|------|
| level | 73 | 电量百分比 |
| status | 2 | 充电中 |
| health | 2 | 良好 |

### 数学公式

质能方程 $E = mc^2$ 是最有名的公式之一。

行内公式也要能和中文混排，比如 $a^2 + b^2 = c^2$ 这样。

$$
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
$$

一元二次方程 $ax^2 + bx + c = 0$（$a \ne 0$）的求根公式：

$$x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$$

### 建议

1. 先把缓存清掉
2. 再检查后台进程
   - 网易云音乐
   - 微信

> 注意：清理缓存会退出登录状态。

```bash
pm clear com.netease.cloudmusic
# Success
```

参考 [Android 存储文档](https://developer.android.com/training/data-storage)。

---

就这些。
''';

void main() {
  testWidgets('markdown preview', (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();

    tester.view.physicalSize = const Size(1170, 3400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Scaffold(
          backgroundColor: AppColors.lightBg,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: const MarkdownView(text: _sample, baseSize: 15),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/markdown_preview.png'),
    );
  });
}

// 让 analyzer 不抱怨未使用的 dart:io（golden 输出路径由测试框架处理）
// ignore: unused_element
final _keep = Directory.systemTemp;
