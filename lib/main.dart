import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'core/productivity.dart';
import 'core/python.dart';
import 'core/rules.dart';
import 'core/storage.dart';
import 'core/store.dart';
import 'core/termux.dart';
import 'plugins/plugin.dart';
import 'shizuku/shizuku_service.dart';
import 'theme/app_theme.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 边到边：内容延伸到状态栏与导航栏后面，配合透明系统栏实现沉浸式。
  // 各页自己用 SafeArea / MediaQuery.padding 保证内容不被系统栏遮住。
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final Settings settings = await Settings.load();

  final Directory docs = await getApplicationDocumentsDirectory();

  final ConversationStore conversations =
      ConversationStore(File('${docs.path}/conversations.json'));
  await conversations.load();

  final PluginStore plugins = PluginStore(File('${docs.path}/plugins.json'));
  await plugins.load();

  final NoteStore notes = NoteStore(File('${docs.path}/notes.json'));
  await notes.load();

  final TaskStore tasks = TaskStore(File('${docs.path}/tasks.json'));
  await tasks.load();

  // 自定义规则。用单例是因为它要在系统提示词构建时读到，
  // 而那条路径在 AgentRunner 深处，透传要改十几个文件。
  await RuleStore.configure(File('${docs.path}/rules.json'));

  // 工作目录选外部私有目录而不是 /data/data：截图是我们自己写盘没问题，
  // 但 screenrecord 是 shell 身份落盘，shell 写不进 app 的私有数据目录。
  // /sdcard/Android/data/<pkg>/files 两边都能访问。
  Directory? ext = await getExternalStorageDirectory();
  ext ??= await getApplicationSupportDirectory();
  final String workDir = '${ext.path}/dsh';

  // 启动时清理 7 天前的截图与录屏。
  // 它们只是工具的中间产物（给模型看完就没用了），历史记录不引用，
  // 所以自动清理不需要打扰用户。聊天附件不在此列，只在用户明确要求时删。
  unawaited(StorageManager.clearOldCaptures(
    workDir,
    const Duration(days: 7),
  ));

  final ShizukuService shizuku = ShizukuService();
  await shizuku.init();

  // 探测 Termux 是否可用。**不 await** —— 它要查包管理器、可能耗时，
  // 而它只影响"注册哪个工具"，不该拖慢启动。探测完会通知监听者。
  unawaited(TermuxService.instance.refresh());

  // 探测内嵌 Python。**也不 await** —— 首次调用要启动解释器，可能一两秒。
  // 同样只影响工具注册，不该挡住启动。
  unawaited(PythonService.instance.refresh());

  runApp(AgentApp(
    settings: settings,
    conversations: conversations,
    plugins: plugins,
    shizuku: shizuku,
    workDir: workDir,
    notes: notes,
    tasks: tasks,
  ));
}

class AgentApp extends StatelessWidget {
  const AgentApp({
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
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      // 换主题色时要重建整棵树 —— 种子色是在 AppTheme._build 里写进
      // AppColors.accent 的，不重建的话已画好的组件会留着旧颜色。
      animation: settings,
      builder: (BuildContext context, Widget? _) {
        final Color seed = Color(settings.seedColor);
        return MaterialApp(
          title: 'PrivTasker',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(seed),
          darkTheme: AppTheme.dark(seed),
          // 跟随系统暗色模式
          themeMode: ThemeMode.system,
          // 系统栏（状态栏/导航栏）的图标颜色必须随主题走：
          // 深色模式下用浅色图标，否则图标压在纯黑背景上根本看不见。
          builder: (BuildContext context, Widget? child) {
            final Brightness brightness =
                MediaQuery.platformBrightnessOf(context);
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: AppTheme.systemUiFor(brightness),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: HomeShell(
            settings: settings,
            conversations: conversations,
            plugins: plugins,
            shizuku: shizuku,
            workDir: workDir,
            notes: notes,
            tasks: tasks,
          ),
        );
      },
    );
  }
}
