import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'core/productivity.dart';
import 'core/storage.dart';
import 'core/store.dart';
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
    return MaterialApp(
      title: 'PrivTasker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // 跟随系统暗色模式
      themeMode: ThemeMode.system,
      // 系统栏（状态栏/导航栏）的图标颜色必须随主题走：
      // 深色模式下用浅色图标，否则图标压在纯黑背景上根本看不见。
      builder: (BuildContext context, Widget? child) {
        final Brightness brightness = MediaQuery.platformBrightnessOf(context);
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
  }
}
