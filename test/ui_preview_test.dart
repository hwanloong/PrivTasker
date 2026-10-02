// UI 预览渲染器。
//
// 目的：在没有真机/模拟器的情况下，把**真实的 Flutter 控件树**渲染成 PNG，
// 用于确认界面效果。它不是断言型测试，只是借 flutter_test 的渲染管线出图。
//
// 生成方式：
//   flutter test test/ui_preview_test.dart --update-goldens
// 产物在 test/goldens/ 下。
import 'dart:io';

import 'package:dsh_agent/core/models.dart';
import 'package:dsh_agent/core/productivity.dart';
import 'package:dsh_agent/core/store.dart';
import 'package:dsh_agent/plugins/plugin.dart';
import 'package:dsh_agent/shizuku/shizuku_service.dart';
import 'package:dsh_agent/theme/app_theme.dart';
import 'package:dsh_agent/ui/home_shell.dart';
import 'package:dsh_agent/ui/history_sheet.dart';
import 'package:dsh_agent/ui/teenspace_page.dart';
import 'package:dsh_agent/ui/widgets.dart';
import 'package:dsh_agent/ui/workspace_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 把 pubsbec 里声明的字体真正加载进来。
/// flutter_test 默认用的是 Ahem 占位字体，不加载的话整张图都是方块。
Future<void> _loadFonts() async {
  final Map<String, List<String>> families = <String, List<String>>{
    'TimesNewRoman': <String>[
      'assets/fonts/times.ttf',
      'assets/fonts/timesbd.ttf',
      'assets/fonts/timesi.ttf',
      'assets/fonts/timesbi.ttf',
    ],
    'SimSun': <String>['assets/fonts/simsun.ttf'],
    'Consolas': <String>[
      'assets/fonts/consola.ttf',
      'assets/fonts/consolab.ttf',
      'assets/fonts/consolai.ttf',
    ],
    // 苹方是**默认字体方案**。不加载它的话，所有文字都会落到 Ahem 占位字体
    // —— 渲染图上是满屏空心方块，而应用本身没问题。这个坑很隐蔽：
    // 换默认字体方案时必须同步加到这里。
    'PingFang': <String>['assets/fonts/pingfang.ttf'],
  };

  for (final MapEntry<String, List<String>> e in families.entries) {
    final FontLoader loader = FontLoader(e.key);
    for (final String asset in e.value) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }

  // 图标字体也要显式加载，否则图标位置全渲染成空方块（测试环境的占位字体导致）
  final FontLoader iconLoader = FontLoader('MaterialIcons');
  iconLoader.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await iconLoader.load();

  // 给两个**系统族名**注册替身。
  //
  // 应用默认的字体方案（sans）用的是 `sans-serif` / `monospace` ——
  // 真机上由系统解析成 Roboto 之类，测试环境里没有系统字体，
  // 不注册就会落到 Ahem 占位字体：每个字都是一个空心方块，渲染图没法看。
  //
  // 拿 SimSun / Consolas 当替身：字形和真机不同，但它**有中文、有等宽**，
  // 足以验证排版、间距和颜色。真机观感只能在设备上确认。
  await (FontLoader('sans-serif')
        ..addFont(rootBundle.load('assets/fonts/simsun.ttf')))
      .load();
  await (FontLoader('monospace')
        ..addFont(rootBundle.load('assets/fonts/consola.ttf')))
      .load();
}

ToolInvocation _inv({
  required String id,
  required String name,
  required Map<String, dynamic> args,
  required RiskAssessment risk,
  required InvocationStatus status,
  String? output,
}) {
  return ToolInvocation(
    id: id,
    name: name,
    argumentsJson: '{}',
    args: args,
    risk: risk,
    status: status,
    output: output,
  );
}

Conversation _seed() {
  final Conversation c = Conversation(id: 'demo', title: '查电量并清缓存');

  c.messages.addAll(<ChatMessage>[
    ChatMessage(
      id: 'u1',
      role: Role.user,
      content: '查一下手机电量，然后把网易云音乐的缓存清掉',
    ),
    ChatMessage(
      id: 'a1',
      role: Role.assistant,
      content: '好的。我先读取电池信息，再清理缓存。',
      tools: <ToolInvocation>[
        _inv(
          id: 't1',
          name: 'run_shell',
          args: <String, dynamic>{
            'command': "dumpsys battery | grep -E 'level|status'",
          },
          risk: RiskAssessment.safe,
          status: InvocationStatus.success,
          output: 'level: 73\nstatus: 2',
        ),
        _inv(
          id: 't2',
          name: 'run_shell',
          args: <String, dynamic>{'command': 'pm clear com.netease.cloudmusic'},
          risk: const RiskAssessment(RiskLevel.dangerous, <String>[
            'pm clear 会清除目标的全部数据（登录状态、本地文件等），不可撤销',
          ]),
          status: InvocationStatus.success,
          output: 'Success',
        ),
      ],
    ),
    ChatMessage(
      id: 'a2',
      role: Role.assistant,
      content: '已清理完成，释放约 **128 MB**。\n\n'
          '### 设备状态\n'
          '- 电池：`level: 73`，*充电中*\n'
          '- 缓存路径：`/data/data/com.netease.cloudmusic/cache`\n'
          '- 建议每周清理一次，不必频繁操作\n\n'
          '```bash\npm clear com.netease.cloudmusic\n# Success\n```\n\n'
          '详见 [Android 存储文档](https://developer.android.com/training/data-storage)。',
    ),
    // 演示「插入网页内容」：抓到的 JSON 会作为消息内容发给模型
    ChatMessage(
      id: 'u2',
      role: Role.user,
      content: '这个接口返回的路线有多长？',
      attachments: <Attachment>[
        Attachment(
          kind: AttachmentKind.web,
          path: 'https://api.mapbox.com/directions/v5/mapbox/driving/120.15,30.27;120.20,30.31',
          name: 'Mapbox Directions API',
          content: '{\n'
              '  "routes": [\n'
              '    {\n'
              '      "distance": 12453.2,\n'
              '      "duration": 983.4,\n'
              '      "weight_name": "routability"\n'
              '    }\n'
              '  ],\n'
              '  "code": "Ok"\n'
              '}',
        ),
      ],
    ),
  ]);

  return c;
}

Future<Widget> _buildApp({
  required Brightness brightness,
  required Settings settings,
  required ConversationStore conversations,
  required PluginStore plugins,
}) async {
  final ShizukuService shizuku = ShizukuService();

  // 和 main.dart 一样：字体方案必须在**构建主题之前**写进 AppFonts。
  //
  // 不调这一步的话，测试用的是 `AppFonts` 的静态初始值（Times / 宋体 / Consolas），
  // 而应用默认方案是 `sans` —— 于是渲染图上的字体从来就不是用户实际会看到的那套，
  // 而且 code 字体里的中文会因为"回退链里没有中文字形"渲染成空心方块。
  AppFonts.applyScheme(settings.fontScheme);
  AppFonts.userScale = settings.fontScale;

  final Widget app = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode:
        brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    // 和 main.dart 保持一致：液态玻璃那个包是 Material-free 的，
    // 不垫这一层透明 Material，测试里的文字会出现黄色下划线。
    builder: (BuildContext context, Widget? child) => Material(
      type: MaterialType.transparency,
      child: child ?? const SizedBox.shrink(),
    ),
    // 渲染**真实的 HomeShell**，而不是单独一个 ChatPage。
    //
    // 之前这里挂的是 ChatPage，于是底部标签栏从来没进过渲染图 ——
    // 界面改了好几轮，图里始终看不到它，等于那一块一直没验证。
    home: HomeShell(
      settings: settings,
      conversations: conversations,
      plugins: plugins,
      shizuku: shizuku,
      workDir: Directory.systemTemp.path,
      notes: NoteStore(File('${Directory.systemTemp.path}/notes.json')),
      tasks: TaskStore(File('${Directory.systemTemp.path}/tasks.json')),
    ),
  );

  // 不开 adaptiveQuality：它会在启动时跑约 3 秒的性能基准测试，
  // 让测试变慢且结果不稳定。和线上一致的关键部分是亮度解析器 ——
  // 没有它，玻璃的明暗会跟着**系统**走而不是跟着应用主题走。
  return LiquidGlassWidgets.wrap(
    child: app,
    brightnessResolver: Theme.maybeBrightnessOf,
  );
}

void main() {
  late Settings settings;
  late ConversationStore conversations;
  late PluginStore plugins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'apiKey': 'sk-demo',
      'model': 'deepseek-flash',
    });
    settings = await Settings.load();

    final Directory tmp = await Directory.systemTemp.createTemp('dsh_preview');
    conversations = ConversationStore(File('${tmp.path}/conv.json'));
    conversations.conversations.add(_seed());
    conversations.currentId = 'demo';

    plugins = PluginStore(File('${tmp.path}/plugins.json'));
  });

  Future<void> render(WidgetTester tester, String name) async {
    // 按手机竖屏尺寸渲染
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await _buildApp(
      brightness: name.contains('dark') ? Brightness.dark : Brightness.light,
      settings: settings,
      conversations: conversations,
      plugins: plugins,
    ));
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('light', (WidgetTester tester) async {
    await render(tester, 'chat_light');
  });

  testWidgets('dark', (WidgetTester tester) async {
    await render(tester, 'chat_dark');
  });

  // 设置页。现在是**独立页面**，不再是底部面板。
  testWidgets('settings page', (WidgetTester tester) async {
    // 这一页打开时会去查后台保活状态和悬浮窗权限。测试环境里没有这两个
    // 原生通道，不拦下来会抛 MissingPluginException 把测试打挂。
    const MethodChannel bg = MethodChannel('dsh/bg');
    const MethodChannel overlay = MethodChannel('dsh/overlay');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(bg, (MethodCall call) async => false);
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(overlay, (MethodCall call) async => false);
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(bg, null);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(overlay, null);
    });

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await _buildApp(
      brightness: Brightness.light,
      settings: settings,
      conversations: conversations,
      plugins: plugins,
    ));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byTooltip('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings_page.png'),
    );
  });

  // 历史记录面板。
  //
  // 挑它当代表有两个原因：内部是一个 **ListView**（覆盖滚动路径），
  // 而且它是**刻意不用玻璃**的那一个 —— 出图能确认它确实是普通面板，
  // 免得以后有人"顺手统一"成玻璃。
  testWidgets('history sheet', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    AppFonts.applyScheme(settings.fontScheme);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        builder: (BuildContext context, Widget? child) => Material(
          type: MaterialType.transparency,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            backgroundColor: AppColors.lightBg,
            body: Center(
              child: TextButton(
                onPressed: () =>
                    showHistorySheet(context, store: conversations),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    // 不用 pumpAndSettle：这个包的面板有持续动画，settle 不会返回。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/history_sheet.png'),
    );
  });

  // TeenSpace：三档敏感度。
  testWidgets('teenspace', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    AppFonts.applyScheme(settings.fontScheme);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        builder: (BuildContext context, Widget? child) => Material(
          type: MaterialType.transparency,
          child: child ?? const SizedBox.shrink(),
        ),
        home: TeenSpacePage(settings: settings),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/teenspace.png'),
    );
  });

  // 工作空间：当前目录 + 写盘校验 + 操作。
  testWidgets('workspace', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    AppFonts.applyScheme(settings.fontScheme);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        builder: (BuildContext context, Widget? child) => Material(
          type: MaterialType.transparency,
          child: child ?? const SizedBox.shrink(),
        ),
        home: WorkspacePage(
          settings: settings,
          defaultWorkDir:
              '/storage/emulated/0/Android/data/com.dsh.dsh_agent/files/dsh',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/workspace.png'),
    );
  });

  // 「+」四标签页面板。
  //
  // 单独出图是因为它只在 showModalBottomSheet 里渲染，chat_light 截不到；
  // 而这一块是这一轮改动最大的地方，不看等于没验证。
  testWidgets('attach panel', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await _buildApp(
      brightness: Brightness.light,
      settings: settings,
      conversations: conversations,
      plugins: plugins,
    ));
    await tester.pump(const Duration(milliseconds: 200));

    // 用 tooltip 定位，比 byIcon 稳 —— IndexedStack 里笔记页也有一个
    // `Icons.add_rounded`（新建笔记）。
    await tester.tap(find.byTooltip('发送图片或文件'));
    // 不用 pumpAndSettle：面板里只要有永不停止的动画它就会挂死进程。
    // 显式推进到路由动画结束就够了。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/attach_panel.png'),
    );
  });

  // 单独渲染「插入网页内容」的卡片：整条会话里它在可视区之外，
  // 只在 chat_light 里截不到。
  testWidgets('web card', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 1560);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final ChatMessage msg = ChatMessage(
      id: 'web',
      role: Role.user,
      content: '这个接口返回的路线有多长？',
      attachments: <Attachment>[
        Attachment(
          kind: AttachmentKind.web,
          path:
              'https://api.mapbox.com/directions/v5/mapbox/driving/120.15,30.27;120.20,30.31',
          name: 'Mapbox Directions API',
          content: '{\n'
              '  "routes": [\n'
              '    {\n'
              '      "distance": 12453.2,\n'
              '      "duration": 983.4,\n'
              '      "weight_name": "routability"\n'
              '    }\n'
              '  ],\n'
              '  "code": "Ok"\n'
              '}',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Scaffold(
          backgroundColor: AppColors.lightBg,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: MessageView(message: msg),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/web_card.png'),
    );
  });
}
