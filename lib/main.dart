import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'core/custom_font.dart';
import 'core/memory.dart';
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

  // 预热液态玻璃的 shader。
  //
  // 放在这里而不是懒加载，是因为它**只是异步的磁盘到内存 I/O**：
  // 不做光栅化、不碰 GPU，所以不会拖慢首帧。不预热的话，第一块玻璃
  // 出现时会明显闪一下（shader 还没编译完）。
  await LiquidGlassWidgets.initialize();

  final Settings settings = await Settings.load();

  // 用户自己选的字体文件（苹方等）。
  //
  // 必须在这里 await 完 —— 主题构建时 textTheme 就要用那个家族名，
  // 晚一步第一帧就会是系统字体，看起来像"设置没生效"。
  // 失败不中断启动：记下原因，设置页会把它显示出来。
  if (settings.customFontPath.trim().isNotEmpty) {
    await CustomFont.loadFrom(settings.customFontPath.trim());
  }

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

  // 长期记忆，同一个理由用单例。
  await MemoryStore.configure(File('${docs.path}/memory.json'));

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

  runApp(
    LiquidGlassWidgets.wrap(
      child: AgentApp(
        settings: settings,
        conversations: conversations,
        plugins: plugins,
        shizuku: shizuku,
        defaultWorkDir: workDir,
        notes: notes,
        tasks: tasks,
      ),
      // 必须给这个解析器。
      //
      // 这个包**一行 `flutter/material.dart` 都没 import**（为了和
      // Cupertino 版共用一套代码），所以它拿不到 MaterialApp 的 ThemeMode，
      // 只能读到系统亮度。不接这一根，就会出现"应用设成亮色、但系统是暗色，
      // 于是玻璃的边框和阴影按暗色渲染"这种错位。
      brightnessResolver: Theme.maybeBrightnessOf,
      // 按设备实测性能自动分级：慢机器降到 minimal，快机器升到 premium。
      // 玻璃的 shader 在低端机上代价不小，不装这个的话老机器会直接掉帧。
      adaptiveQuality: true,
      // ---- 玻璃的观感参数：**一个都不覆盖** ----
      //
      // 这里我连着调坏了三轮，所以留下结论：**不要再手调这套参数。**
      //
      //   1. 为了"更沉浸"把 `blur` 从 5 提到 20 → 用户看到"很多控件发白"。
      //      （`blur` 是**玻璃自身**的霜化半径，调大只会让玻璃本体变浑变白。
      //        真正管"背景模不模糊"的是 `frost`，只有 premium 路径才生效。）
      //   2. 于是关掉 `frost`、把质量压到 `standard` → 背景完全不糊了。
      //   3. 再把质量提到 `premium` 让 `frost` 生效 → 用户说"整个 UI 都烂了"。
      //
      // 第 3 步踩的是包文档里**明确写过的**一条：
      //
      //   > Use Premium only for static, non-scrolling surfaces.
      //   > It may not render correctly inside ListView or CustomScrollView on Impeller.
      //
      // 而这个应用的设置页、附件面板、笔记页**全是 ListView**，里面密布着
      // 玻璃按钮和分段控件 —— 全局 premium 正好命中那个已知会渲染错的情况。
      //
      // 根本问题在于：**这些参数在测试渲染器里完全看不出来**（它跑的不是
      // 真 shader 路径），所以我只能靠猜。三轮都猜错了，说明这个位置不该猜 ——
      // 包的作者是在真机上验证过那套默认值的，而我没有真机。
      //
      // 所以：不传 `theme:`。每个控件用它自己那套默认
      // （标签栏默认 premium 且不在列表里，安全；列表里的按钮走各自的默认）。
      // 需要"背后糊一点"这类观感调整时，先在真机上看到实际效果再动。
    ),
  );
}

class AgentApp extends StatelessWidget {
  const AgentApp({
    super.key,
    required this.settings,
    required this.conversations,
    required this.plugins,
    required this.shizuku,
    required this.defaultWorkDir,
    required this.notes,
    required this.tasks,
  });

  final Settings settings;
  final ConversationStore conversations;
  final PluginStore plugins;
  final ShizukuService shizuku;

  /// 用户在设置里没指定工作空间时用的目录（应用外部私有目录下的 dsh）。
  final String defaultWorkDir;

  final NoteStore notes;
  final TaskStore tasks;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      // 设置一变就重建整棵树。字体方案、字号、**工作空间**都靠这一步生效 ——
      // 它们都是在 build 里被读出来往下传的，不重建就不会更新。
      animation: settings,
      builder: (BuildContext context, Widget? _) {
        // 字体方案和字号必须在**构建主题之前**写进 AppFonts ——
        // 主题里的 textTheme 会读它，晚一步就还是旧字体。
        AppFonts.applyScheme(settings.fontScheme);
        AppFonts.userScale = settings.fontScale;

        // 工作目录：用户指定了就用它，否则用默认的那个。
        //
        // 在这里算而不是在 main() 里算死，是因为**它得跟着设置变**：
        // 用户在设置里换了工作空间，整棵树会重建，这个值也就跟着换，
        // 之后所有工具（截图、录屏、插件脚本）都落到新目录。
        // 在 main() 里算死的话，改了要重启应用才生效 —— 那不像"设置"，像配置。
        final String workDir = settings.workspacePath.trim().isEmpty
            ? defaultWorkDir
            : settings.workspacePath.trim();

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
            final Brightness brightness =
                MediaQuery.platformBrightnessOf(context);
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: AppTheme.systemUiFor(brightness),
              // 垫一层**透明 Material**。
              //
              // liquid_glass_widgets 是 Material-free 的，不提供 Material 祖先；
              // 而 MaterialApp 下的 Text 找不到 Material 时会渲染出调试用的
              // 黄色下划线 —— 界面看起来像坏了。这一层只提供祖先，不上色。
              child: Material(
                type: MaterialType.transparency,
                child: child ?? const SizedBox.shrink(),
              ),
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
