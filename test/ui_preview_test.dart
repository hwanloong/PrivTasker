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
import 'package:dsh_agent/ui/chat_page.dart';
import 'package:dsh_agent/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode:
        brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    home: ChatPage(
      settings: settings,
      conversations: conversations,
      plugins: plugins,
      shizuku: shizuku,
      workDir: Directory.systemTemp.path,
      notes: NoteStore(File('${Directory.systemTemp.path}/notes.json')),
      tasks: TaskStore(File('${Directory.systemTemp.path}/tasks.json')),
    ),
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
