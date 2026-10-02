import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
// 液态玻璃按前缀导入：这个包也导出 `GlassButton` / `GlassIconButton`，
// 而本项目在 theme/glass.dart 里有同名但 API 不同的控件。
// 不隔离的话，本文件里所有 `GlassButton` 的用法会瞬间指向错误的那个。
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;
import 'package:url_launcher/url_launcher.dart';

import '../ai/agent.dart';
import '../core/background.dart';
import '../core/metrics.dart';
import '../core/models.dart';
import '../core/overlay.dart';
import '../core/productivity.dart';
import '../core/python.dart';
import '../core/store.dart';
import '../core/termux.dart';
import '../core/web_fetch.dart';
import '../plugins/plugin.dart';
import '../shizuku/shizuku_service.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../tools/android_tools.dart';
import '../tools/browser_tool.dart';
import '../tools/extra_tools.dart';
import '../tools/memory_tool.dart';
import '../tools/productivity_tools.dart';
import '../tools/python_tool.dart';
import '../tools/rule_tool.dart';
import '../tools/termux_tool.dart';
import '../tools/tool.dart';
import 'history_sheet.dart';
import 'performance_sheet.dart';
import 'settings_sheet.dart';
import 'widgets.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
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
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// 待发送的附件（还没发出去）
  final List<Attachment> _pending = <Attachment>[];

  /// 正在抓取网页附件
  bool _fetchingWeb = false;

  AgentRunner? _runner;
  bool _busy = false;

  /// 「+」面板上次停在哪个标签页。
  ///
  /// 记在 State 里而不是每次重置为 0：用户连调两次参数是常态，
  /// 每次都弹回第一个标签会让他重新点一遍。
  int _attachTab = 0;

  /// 是否已经滚到底部。用来决定要不要显示「回到底部」按钮。
  bool _atBottom = true;

  /// 悬浮窗权限状态；null 表示还没查到。
  /// 没权限时确认框只能退回应用内弹窗，很容易被别的应用盖住，所以要提示用户。
  bool? _overlayGranted;

  @override
  void initState() {
    super.initState();
    // 观察生命周期：进度浮窗只在**应用不在前台**时显示。
    // 前台时界面本身就有进度（工具卡片、转圈），再压一个浮窗是纯噪音。
    WidgetsBinding.instance.addObserver(this);
    widget.settings.addListener(_onExternalChange);
    widget.conversations.addListener(_onExternalChange);
    widget.plugins.addListener(_onExternalChange);
    widget.shizuku.addListener(_onExternalChange);
    _scroll.addListener(_onScroll);

    if (widget.conversations.conversations.isEmpty) {
      widget.conversations.createNew();
    }

    OverlayService.canDraw().then((bool v) {
      if (mounted) setState(() => _overlayGranted = v);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 离开页面时一定要收掉浮窗 —— 否则它会一直挂在屏幕上，
    // 而且再也没人能关掉它（那个 State 已经销毁了）
    OverlayService.dismissActivity();
    widget.settings.removeListener(_onExternalChange);
    widget.conversations.removeListener(_onExternalChange);
    widget.plugins.removeListener(_onExternalChange);
    widget.shizuku.removeListener(_onExternalChange);
    _scroll.removeListener(_onScroll);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final ScrollPosition p = _scroll.position;
    // 留点余量，不要求严丝合缝贴底
    final bool atBottom = p.pixels >= p.maxScrollExtent - 48;
    if (atBottom != _atBottom && mounted) {
      setState(() => _atBottom = atBottom);
    }
  }

  void _onExternalChange() {
    if (mounted) setState(() {});
  }

  /// 最近一次的"正在干什么"文案。
  /// 切到后台时要立刻显示浮窗，那时得有个已知的文案可用，
  /// 不能等下一次 onUpdate（可能还要几秒）。
  String _lastActivity = '正在工作…';

  /// 应用是否在前台。
  ///
  /// 浮窗的显示条件就是它 —— **应用内绝不显示浮窗**：
  /// 界面上本来就有进度（工具卡片、转圈），再压一个浮窗是纯视觉噪音。
  bool _appInForeground = true;

  /// 应用前后台切换。
  ///
  /// ⚠️ **判断必须只看 paused / hidden，不能用 `state == resumed`。**
  ///
  /// `AppLifecycleState` 有五档，中间那个 `inactive` 很容易被忽略：
  /// 拉下通知栏、弹系统对话框、权限提示、分屏 —— 这些都会进 `inactive`，
  /// **而应用仍然可见**。把 `!resumed` 当后台，就会出现
  /// "拉一下通知栏，浮窗冒出来了"。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    final bool background = state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden;

    _appInForeground = !background;

    if (background && _busy) {
      // 真的切出去了且正在干活 → 才显示浮窗
      OverlayService.showActivity(_lastActivity);
    } else if (!background) {
      // resumed 和 inactive 都收起 —— inactive 时应用还看得见，
      // 界面上的进度已经够了
      OverlayService.hideActivity();
    }
  }

  Conversation get _conv {
    final Conversation? c = widget.conversations.current;
    if (c != null) return c;
    return widget.conversations.createNew();
  }

  // ------------------------------------------------------------------ 工具表

  ToolRegistry _buildRegistry() {
    final ToolRegistry r = ToolRegistry();

    // 需要 shell 的工具只在 Shizuku 就绪时注册。
    // 未就绪时注册它们只会让模型反复调用然后拿到一堆「无法执行」，
    // 白白浪费轮次，还会让用户以为整个应用不能用。
    if (widget.shizuku.ready) {
      r.registerAll(<AgentTool>[
        const ShellTool(),
        const AppManagerTool(),
        const FileTool(),
        const SettingsTool(),
        const CaptureTool(),
      ]);
    }

    // 这两个不依赖 Shizuku，任何情况下都可直接用
    r.registerAll(<AgentTool>[
      const WebTool(),
      const BrowserTool(),
      const ImageTool(),
      // 笔记与任务：agent 要能真的写进去，"记一下""提醒我"才有意义
      const NotesTool(),
      const TasksTool(),
    ]);

    // Termux 不依赖 Shizuku，但它依赖"用户装了 Termux"。
    // 只有真的可用（或还没验证过）时才注册 —— 否则模型会去调它、
    // 拿到一句"未安装"，白白浪费一轮。
    if (TermuxService.instance.canAttempt) {
      r.register(const TermuxTool());
    }

    // 内嵌 Python 是**应用自带**的，**无条件注册**。
    //
    // 这里原来写成"可用时才注册"，结果是个很糟的失败模式：
    // Python 起不来 → 工具从注册表消失 → agent 压根不知道有这东西
    // → 用户看到的是"agent 引用不了 python"，**完全看不到真正的原因**。
    //
    // 把失败藏起来比失败本身更糟。现在无条件注册，
    // 真出问题时工具会返回明确的错误信息，用户和模型都能看到。
    r.register(const PythonTool());

    // 自定义规则：让 agent 能把用户的长期偏好**落成真实规则**，
    // 而不是嘴上说"记住了"下一轮就忘。所有写操作都会被风险分级
    // 拦下并要求用户确认。
    r.register(const RuleTool());

    // 长期记忆。和 RuleTool 同一个理由：让 agent 自己判断什么值得记，
    // 而不是让用户去设置页手填。
    r.register(const MemoryTool());

    for (final PluginTool t in widget.plugins.enabledTools()) {
      if (r.byName(t.name) != null) continue;
      if (!widget.shizuku.ready && t.plugin.kind == PluginKind.shell) continue;
      r.register(t);
    }

    return r;
  }

  // ------------------------------------------------------------------ 附件

  Future<Attachment?> _persist(XFile x, {required AttachmentKind kind}) async {
    try {
      final Uint8List bytes = await x.readAsBytes();
      final Directory dir = Directory('${widget.workDir}/attachments');
      await dir.create(recursive: true);

      final String rawName = x.name.isEmpty ? 'file' : x.name;
      final String ext = rawName.contains('.')
          ? rawName.split('.').last
          : (kind == AttachmentKind.image ? 'jpg' : 'dat');
      final String path =
          '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.$ext';
      await File(path).writeAsBytes(bytes);

      return Attachment(
        kind: kind,
        path: path,
        name: rawName,
        size: bytes.length,
      );
    } catch (e) {
      _snack('保存附件失败：$e');
      return null;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? x = await ImagePicker().pickImage(
        source: source,
        imageQuality: 92,
      );
      if (x == null) return;
      final Attachment? a = await _persist(x, kind: AttachmentKind.image);
      if (a != null && mounted) setState(() => _pending.add(a));
    } catch (e) {
      _snack('选取图片失败：$e');
    }
  }

  Future<void> _pickFile() async {
    try {
      final XFile? x = await openFile();
      if (x == null) return;
      final String lower = x.name.toLowerCase();
      final bool isImage = <String>['jpg', 'jpeg', 'png', 'gif', 'webp']
          .any((String e) => lower.endsWith('.$e'));
      final Attachment? a = await _persist(
        x,
        kind: isImage ? AttachmentKind.image : AttachmentKind.file,
      );
      if (a != null && mounted) setState(() => _pending.add(a));
    } catch (e) {
      _snack('选取文件失败：$e');
    }
  }

  /// 插入网页/接口内容。
  ///
  /// 抓取在**插入时**完成而不是发送时：这样用户能立刻看到抓到了什么，
  /// 内容也会随会话一起存下来——历史记录不需要重新联网，
  /// 也不会因为原页面后来改版而对不上。
  Future<void> _addWebLink() async {
    final String? url = await _promptUrl();
    if (url == null || url.trim().isEmpty) return;

    setState(() => _fetchingWeb = true);
    WebContent result;
    try {
      result = await WebFetcher.fetch(url.trim());
    } finally {
      if (mounted) setState(() => _fetchingWeb = false);
    }

    if (!mounted) return;

    if (!result.ok) {
      _snack('抓取失败：${result.error ?? '未知原因'}');
      // 抓取失败也让用户决定要不要把网址本身发出去
      final bool keep = await _confirmKeepUrl(url.trim());
      if (!keep || !mounted) return;
    }

    setState(() {
      _pending.add(Attachment(
        kind: AttachmentKind.web,
        path: result.url.isEmpty ? url.trim() : result.url,
        name: result.title.trim().isEmpty ? url.trim() : result.title.trim(),
        content: result.text,
        size: result.text.length,
      ));
    });
  }

  Future<bool> _confirmKeepUrl(String url) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(
          '抓取失败',
          style: AppFonts.body(size: 16.5, weight: FontWeight.w600, height: 1.3),
        ),
        content: Text(
          '没能抓到 $url 的内容。\n\n'
          '仍然把网址本身插入消息吗？（模型只会看到这个链接，看不到内容）',
          style: AppFonts.body(size: 13.5, height: 1.6),
        ),
        actions: <Widget>[
          GlassButton(
            label: '算了',
            onTap: () => Navigator.of(ctx).pop(false),
          ),
          GlassButton(
            label: '插入网址',
            accent: true,
            onTap: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<String?> _promptUrl() async {
    final TextEditingController c = TextEditingController();
    final AppSurface s = AppSurface.of(context);

    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(
          '插入网页或接口',
          style: AppFonts.body(size: 16.5, weight: FontWeight.w600, height: 1.3),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '贴一个网址。JSON 接口会直连获取，网页会用内置浏览器渲染后取正文。'
              '抓到的内容会作为消息内容发给模型。',
              style: AppFonts.body(size: 12.8, color: s.muted, height: 1.55),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: s.surface,
                borderRadius: BorderRadius.circular(AppRadius.code),
                border: Border.all(color: s.border, width: 0.9),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: c,
                autofocus: true,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onSubmitted: (String v) => Navigator.of(ctx).pop(v),
                style: AppFonts.code(size: 13, color: s.text),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  hintText: 'https://api.mapbox.com/…',
                  hintStyle: AppFonts.code(size: 12.5, color: s.muted),
                ),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          GlassButton(
            label: '取消',
            onTap: () => Navigator.of(ctx).pop(),
          ),
          GlassButton(
            label: '抓取',
            accent: true,
            onTap: () => Navigator.of(ctx).pop(c.text),
          ),
        ],
      ),
    );
    c.dispose();
    return result;
  }

  /// 把「思考深度」映射成滑条的 0~3 档。
  ///
  /// 用户要的是**一根滑条**，而后端只有 low/high/max 三个值 ——
  /// 所以中间做一次映射，而不是把三档硬塞成三个按钮。
  /// 0 = 关闭，1/2/3 = 浅/深/最深。
  static int _effortSliderValue(Settings set) {
    if (!set.thinkingEnabled) return 0;
    return switch (set.reasoningEffort) {
      'low' => 1,
      'max' => 3,
      _ => 2,
    };
  }

  static const List<String> _effortNames = <String>[
    '关闭',
    '浅（快）',
    '深（默认）',
    '最深（慢）',
  ];

  Widget _paramRow(AppSurface s, String label, String value) {    return Row(
      children: <Widget>[
        Text(label, style: AppFonts.body(size: 13.5, color: s.text)),
        const Spacer(),
        Text(value,
            style: AppFonts.code(size: 12.5, color: AppColors.accent)),
      ],
    );
  }

  /// 参数面板里的微调按钮。
  ///
  /// 1~100 的跨度上，滑杆很难精确点到某个值（想要 37 时手指一滑就 40 了），
  /// 所以补 ± 按钮。
  Widget _stepButton(AppSurface s, String label, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: ShapeDecoration(
          color: s.codeBg,
          shape: const StadiumBorder(),
        ),
        child: Text(
          label,
          style: AppFonts.body(
            size: 13.5,
            weight: FontWeight.w600,
            color: s.text,
            height: 1.2,
          ),
        ),
      ),
    );
  }

  Widget _paramHint(AppSurface s, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: mdText(
        text,
        style: AppFonts.body(size: 11, color: s.muted, height: 1.55),
      ),
    );
  }

  /// 选模型。
  ///
  /// 只列当前 DeepSeek 在售的型号 —— `deepseek-chat` / `deepseek-reasoner`
  /// 那两个旧名已经废弃，列出来只会让人选错。
  Future<void> _pickModel() async {
    const List<(String, String)> presets = <(String, String)>[
      ('deepseek-flash', 'V4.1 Flash · 1M 上下文 · 支持视觉'),
      ('deepseek-v4-pro', 'V4 Pro · 推理更强 · 不支持图片'),
    ];

    final String? picked = await _pickSheet(
      title: '选择模型',
      current: widget.settings.model,
      options: presets,
      note: '模型会影响回答质量和速度。图片理解只在支持视觉的模型上可用。',
    );
    if (picked != null) {
      await widget.settings.update(() => widget.settings.model = picked);
      if (mounted) setState(() {});
    }
  }

  /// 通用的单选面板。模型和思考深度共用 —— 两个面板长得一模一样，
  /// 各写一遍迟早会不一致。
  Future<String?> _pickSheet({
    required String title,
    required String current,
    required List<(String, String)> options,
    String? note,
  }) {
    final AppSurface s = AppSurface.of(context);

    return showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: s.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: AppFonts.body(
                  size: 16,
                  weight: FontWeight.w600,
                  color: s.text,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              ...options.map(((String, String) o) {
                final bool active = o.$1 == current;
                return InkWell(
                  onTap: () => Navigator.of(ctx).pop(o.$1),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                o.$1 == '__off__' ? o.$2.split(' · ').first : o.$1,
                                style: AppFonts.code(
                                  size: 13,
                                  color: active ? AppColors.accent : s.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                o.$1 == '__off__'
                                    ? o.$2.split(' · ').skip(1).join(' · ')
                                    : o.$2,
                                style: AppFonts.body(
                                    size: 11.5, color: s.muted, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                        if (active)
                          Icon(Icons.check_circle_rounded,
                              size: 19, color: AppColors.accent),
                      ],
                    ),
                  ),
                );
              }),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
                  child: Text(
                    note,
                    style: AppFonts.body(size: 11.5, color: s.muted, height: 1.55),
                  ),
                ),
            ],
          ),
        ),
    );
  }

  /// 「+」面板：四个标签页。
  ///
  /// 之前是一串平铺的选项，模型、参数、附件混在一起。改成标签页是因为
  /// **这四类东西性质不同**：
  /// · 模型设置 —— 这一轮**怎么想**
  /// · 附件添加 —— 给模型**看什么**
  /// · 工具调用 —— 它**能做什么**
  /// · 性能工具 —— **花了多少**
  ///
  /// 平铺时用户每次都要在一堆无关选项里找自己那一项；分组之后
  /// 手指落到哪个标签是有预期的。
  void _showAttachMenu() {
    // **不用液态玻璃。**
    //
    // 这个面板通篇是内容（模型名、滑杆、附件选项、工具列表），
    // 玻璃是为"浮在内容之上的控制层"准备的 —— 内容层该是不透明的。
    // 半透明的底会让里面的白卡片和文字对比度不稳，读起来更费劲。
    showModalBottomSheet<void>(
      context: context,
      // 标签页之间内容高度差别很大，锁死高度会让高的那页被裁掉。
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        // 标签索引放在 StatefulBuilder **外面**：放里面的话每次
        // setSheet 都会重新初始化回 0，点了没反应。
        //
        // 这里 clamp 一下：标签从 4 个减到 3 个之后，上次停在第 4 个的话
        // 现在就越界了（`switch` 会落到默认分支，但索引本身得先夹住）。
        int tab = _attachTab.clamp(0, 2);
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setSheet) {
            final AppSurface s = AppSurface.of(ctx);
            final Settings set = widget.settings;

            void save(void Function() mutate) {
              set.update(mutate);
              setSheet(() {});
              setState(() {}); // 「+」面板外的描述文字也要跟着更新
            }

            return SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.78,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 12),
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: s.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: lg.GlassSegmentedControl(
                        // 顺序：**附件添加放第一位**。
                        //
                        // 这是「+」按钮最常被按的原因 —— 用户点它多半是想发张图
                        // 或发个文件。模型设置和工具调用是"偶尔调一次"的东西，
                        // 排在后面。
                        //
                        // 「性能工具」标签已删除：性能是**观察**类信息，
                        // 不该和"我要发东西"混在一个面板里。它仍然可以从
                        // 顶部的性能按钮打开。
                        segments: const <lg.GlassSegment>[
                          lg.GlassSegment(label: '附件添加'),
                          lg.GlassSegment(label: '模型设置'),
                          lg.GlassSegment(label: '工具调用'),
                        ],
                        // 和按钮一样用**真胶囊**。
                        // 见 theme/glass.dart 里 GlassButton 那段注释：
                        // 要用包自己的哨兵常量，别自己写数字。
                        borderRadius: lg.GlassDefaults.capsuleRadius,
                        selectedIndex: tab,
                        onSegmentSelected: (int i) {
                          _attachTab = i;
                          setSheet(() => tab = i);
                        },
                        // **必须显式给字体**。
                        //
                        // 这个控件来自 liquid_glass_widgets，它走的是 Cupertino
                        // 的默认字体，不继承本项目的 `AppFonts`。不给的话，
                        // 用户一选「衬线」或「自定义字体」，这四个标签就会
                        // 变成另一套字 —— 界面里冒出几处不一致，还很难看出是哪里。
                        selectedTextStyle: AppFonts.body(
                          size: 12,
                          weight: FontWeight.w600,
                          color: AppColors.accent,
                          height: 1.2,
                        ),
                        unselectedTextStyle: AppFonts.body(
                          size: 12,
                          color: s.muted,
                          height: 1.2,
                        ),
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        child: switch (tab) {
                          0 => _attachFilesTab(ctx, s),
                          1 => _attachModelTab(s, save),
                          _ => _attachToolsTab(s),
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 这个会话目前占了多少 token（粗略估算）。
  int _contextTokens() => _conv.messages.fold<int>(
        0,
        (int sum, ChatMessage m) => sum + AppMetrics.estimate(m.content),
      );

  /// 标签页 1：模型设置。
  Widget _attachModelTab(AppSurface s, void Function(void Function()) save) {
    final Settings set = widget.settings;
    final int effort = _effortSliderValue(set);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // ---- 模型 ----
        _attachOption(
          s,
          icon: Icons.memory_rounded,
          label: '模型',
          desc: set.model,
          pad: false,
          onTap: _pickModel,
        ),

        const SizedBox(height: 8),

        // ---- 思考深度 ----
        _paramRow(s, '思考深度', _effortNames[effort]),
        Slider(
          value: effort.toDouble(),
          min: 0,
          max: 3,
          divisions: 3,
          label: _effortNames[effort],
          onChanged: (double v) {
            final int idx = v.round();
            save(() {
              if (idx == 0) {
                set.thinkingEnabled = false;
              } else {
                set.thinkingEnabled = true;
                set.reasoningEffort =
                    <String>['low', 'low', 'high', 'max'][idx];
              }
            });
          },
        ),
        _paramHint(s, '先"想"再答，质量更好但更慢、更费 token。'),

        const SizedBox(height: 14),

        // ---- 温度 ----
        _paramRow(s, '温度', set.temperature.toStringAsFixed(1)),
        Slider(
          value: set.temperature.clamp(0.0, 2.0),
          min: 0,
          max: 2,
          divisions: 20,
          label: set.temperature.toStringAsFixed(1),
          onChanged: (double v) => save(() => set.temperature = v),
        ),
        _paramHint(
          s,
          '越低越稳定保守，越高越发散有创意。'
          // 这条必须说清楚，否则用户会觉得"调了没用"
          '⚠️ **思考模式开启时这个值不生效** —— '
          '官方说明"设置不报错但也不生效"，想要它起作用先把思考深度调到关闭。',
        ),

        const SizedBox(height: 14),

        // ---- 工具调用轮数 ----
        _paramRow(s, '工具调用上限', '${set.maxToolRounds} 轮'),
        Slider(
          value: set.maxToolRounds.toDouble().clamp(1, 100),
          min: 1,
          max: 100,
          divisions: 99,
          label: '${set.maxToolRounds}',
          onChanged: (double v) => save(() => set.maxToolRounds = v.round()),
        ),
        // 滑杆在 1~100 这个跨度上不好精确点，所以补两个微调按钮。
        // 想要 37 这种具体值时光靠滑杆会调不准。
        Row(
          children: <Widget>[
            _stepButton(s, '−', () {
              if (set.maxToolRounds > 1) {
                save(() => set.maxToolRounds = set.maxToolRounds - 1);
              }
            }),
            const SizedBox(width: 8),
            _stepButton(s, '＋', () {
              if (set.maxToolRounds < 100) {
                save(() => set.maxToolRounds = set.maxToolRounds + 1);
              }
            }),
            const Spacer(),
            _stepButton(s, '常用', () {
              save(() => set.maxToolRounds = 8);
            }),
          ],
        ),
        _paramHint(
          s,
          '一轮 = 模型调一次工具。复杂任务（多步搜索、写代码再调试）需要更多轮；'
          '调太小会让它做一半就停。默认 8 轮，上限 100。',
        ),
      ],
    );
  }

  /// 标签页 2：附件添加。
  Widget _attachFilesTab(BuildContext ctx, AppSurface s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _attachOption(
          s,
          icon: Icons.photo_library_outlined,
          label: '从相册选图片',
          desc: '模型能直接看图',
          pad: false,
          onTap: () {
            Navigator.of(ctx).pop();
            _pickImage(ImageSource.gallery);
          },
        ),
        const SizedBox(height: 8),
        _attachOption(
          s,
          icon: Icons.photo_camera_outlined,
          label: '拍照',
          pad: false,
          onTap: () {
            Navigator.of(ctx).pop();
            _pickImage(ImageSource.camera);
          },
        ),
        const SizedBox(height: 8),
        _attachOption(
          s,
          icon: Icons.attach_file_rounded,
          label: '选择文件',
          desc: '文本类文件会把内容读给模型',
          pad: false,
          onTap: () {
            Navigator.of(ctx).pop();
            _pickFile();
          },
        ),
        const SizedBox(height: 8),
        _attachOption(
          s,
          icon: Icons.link_rounded,
          label: '网页或接口链接',
          desc: '抓取内容后发给模型，如 Mapbox API',
          pad: false,
          onTap: () {
            Navigator.of(ctx).pop();
            _addWebLink();
          },
        ),
      ],
    );
  }

  /// 标签页 3：工具调用。
  ///
  /// 列的是**这一次对话真正注册进来的工具**，而不是一张写死的清单 ——
  /// 所以"有没有 Shizuku"这种状态会直接反映在列表长度上，
  /// 而不是靠一句含糊的提示。
  Widget _attachToolsTab(AppSurface s) {
    final List<AgentTool> tools = _buildRegistry().all;
    final bool z = widget.shizuku.ready;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '本次对话可用 ${tools.length} 个工具',
          style: AppFonts.body(size: 12.8, color: s.muted, height: 1.3),
        ),
        const SizedBox(height: 10),
        for (final AgentTool t in tools)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: SurfaceCard(
              padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          t.title,
                          style: AppFonts.body(
                            size: 13.5,
                            weight: FontWeight.w600,
                            color: s.text,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t.name,
                          style: AppFonts.code(size: 11.5, color: s.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (!z) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            '未取得系统权限，所以 shell / 应用管理 / 文件读写 / 系统设置 / 截屏 '
            '这几个工具现在不在列表里。授予权限后它们会自动出现。',
            style:
                AppFonts.body(size: 12, color: AppColors.warning, height: 1.5),
          ),
        ],
        if (!PythonService.instance.available) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            '内嵌 Python 当前不可用'
            '（${PythonService.instance.lastError ?? "未知原因"}）。'
            '到「设置 → Python 控制台」能看到完整报错。',
            style:
                AppFonts.body(size: 12, color: AppColors.warning, height: 1.5),
          ),
        ],
      ],
    );
  }

  Widget _attachOption(
    AppSurface s, {
    required IconData icon,
    required String label,
    String? desc,
    required VoidCallback onTap,
    // 默认自带左右 16 的外边距，方便直接平铺。
    // 放进标签页时要传 false —— 外面那层滚动容器已经有 padding 了，
    // 两处叠加会变成 32，卡片被挤得又窄又难看。
    bool pad = true,
  }) {
    final Widget card = SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 19, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: AppFonts.body(
                    size: 14,
                    weight: FontWeight.w600,
                    color: s.text,
                    height: 1.3,
                  ),
                ),
                if (desc != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style:
                        AppFonts.body(size: 12, color: s.muted, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (!pad) return card;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: card,
    );
  }

  // ------------------------------------------------------------------ 发送

  Future<void> _send() async {
    final String text = _input.text.trim();
    final List<Attachment> atts = List<Attachment>.from(_pending);
    if ((text.isEmpty && atts.isEmpty) || _busy) return;

    if (!widget.settings.configured) {
      _snack('还没有配置 API Key，请先到设置里填写');
      await showSettingsSheet(
        context,
        settings: widget.settings,
        workDir: widget.workDir,
        plugins: widget.plugins,
        conversations: widget.conversations,
        notes: widget.notes,
        tasks: widget.tasks,
      );
      return;
    }

    final Conversation conv = _conv;
    setState(() {
      conv.messages.add(ChatMessage(
        id: 'u_${DateTime.now().microsecondsSinceEpoch}',
        role: Role.user,
        content: text,
        attachments: atts,
      ));
      _pending.clear();
      _busy = true;
    });
    _input.clear();
    widget.conversations.touch(conv);
    _scrollToEnd();

    final AgentRunner runner = AgentRunner(
      settings: widget.settings,
      shizuku: widget.shizuku,
      registry: _buildRegistry(),
      workDir: widget.workDir,
      notes: widget.notes,
      tasks: widget.tasks,
    );
    _runner = runner;

    // 开始后台保活。**agent 一开始跑就挂上**，而不是等它变慢才挂 ——
    // 因为进程被回收往往发生在任务中途，那时候再挂已经晚了。
    await BackgroundService.instance.start('正在思考…');

    try {
      await runner.run(
        conversation: conv,
        onUpdate: () {
          if (!mounted) return;
          setState(() {});
          _scrollToEnd();
          widget.conversations.save();
          // 通知和悬浮窗都要显示"现在在干什么" ——
          // 状态就在消息对象里（哪个工具是 running），不用改 agent 循环
          _syncAgentActivity(conv);
        },
        onConfirm: (ToolInvocation inv) async {
          if (!mounted) return false;
          final AgentTool? tool = _buildRegistry().byName(inv.name);
          final String title = tool?.title ?? inv.name;
          final String command =
              inv.args['command']?.toString() ?? inv.argumentsJson;

          // 优先走系统悬浮窗：工具很容易把别的应用切到前台
          // （am start、拉起设置页等），应用内弹窗会被盖住，
          // 用户必须先切回来才能确认。悬浮窗始终在最上层。
          if (widget.settings.useOverlayConfirm &&
              await OverlayService.canDraw()) {
            return OverlayService.showConfirm(
              title: title,
              command: command,
              reasons: inv.risk.reasons,
              dangerous: inv.risk.isDangerous,
            );
          }

          if (!mounted) return false;
          return showRiskConfirmDialog(
            context,
            invocation: inv,
            toolTitle: title,
          );
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          conv.messages.add(ChatMessage(
            id: 'e_${DateTime.now().microsecondsSinceEpoch}',
            role: Role.assistant,
            error: e.toString(),
          ));
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.conversations.touch(conv);
      }
      _runner = null;
      // 任务结束就撤掉前台服务和浮窗 —— 常驻通知不该在我们已经不干活时
      // 还挂着，浮窗更是没人会去关它。放在 finally 里，报错和中止也会走到。
      await BackgroundService.instance.stop();
      await OverlayService.dismissActivity();

      // **干完了就把用户带回来。**
      // 他切出去等结果，完成时不该还需要自己想起来切回来看看。
      //
      // 只在应用不在前台时拉 —— 已经在前台还 startActivity 是多余的，
      // 而且可能打断用户正在做的事。
      if (!_appInForeground) {
        await OverlayService.bringToFront();
      }
    }
  }

  /// 从会话的最后一个工具调用里读出"现在在干什么"，同步给通知和悬浮窗。
  ///
  /// 数据来源是 `ToolInvocation.status` —— agent 循环会把它置成 running/success，
  /// 所以**不需要给 AgentRunner 加回调**，读现成的状态就够了。
  void _syncAgentActivity(Conversation conv) {
    if (conv.messages.isEmpty) return;

    final ChatMessage last = conv.messages.last;
    final List<ToolInvocation> tools = last.tools;

    // 找正在跑的那个
    for (final ToolInvocation inv in tools.reversed) {
      if (inv.status == InvocationStatus.running) {
        final AgentTool? t = _buildRegistry().byName(inv.name);
        final String label = t?.title ?? inv.name;
        final String detail = inv.args['command']?.toString() ??
            inv.args['query']?.toString() ??
            inv.args['path']?.toString() ??
            '';
        final String text = detail.isEmpty
            ? '正在执行：$label'
            : '正在执行：$label · ${detail.length > 40 ? '${detail.substring(0, 40)}…' : detail}';
        _pushActivity(text);
        return;
      }
    }

    // 没有正在跑的工具 —— 说明在等模型
    _pushActivity('正在思考…');
  }

  /// 把"现在在干什么"同时推给**通知**和**浮窗**。
  ///
  /// 两个地方用同一份文案 —— 分开维护迟早会出现"通知说在搜索、
  /// 浮窗说在写代码"这种自相矛盾。
  void _pushActivity(String text) {
    _lastActivity = text;
    BackgroundService.instance.update(text);
    // 浮窗只在后台显示，但这里不判断前后台 ——
    // 原生侧会记住状态：没显示时 update 只是更新文案，
    // 等切到后台时会用最新的文案显示出来
    OverlayService.updateActivity(text);
  }

  void _stop() {
    _runner?.abort();
    setState(() => _busy = false);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ------------------------------------------------------------------ 构建

  // 顶部/底部栏的实测高度。
  //
  // 为什么要量：玻璃的模糊只能作用于"从它下面经过的内容"。
  // 原来头部和输入栏是 Column 的兄弟节点，消息列表夹在中间 ——
  // **列表永远不会滚到栏下面**，BackdropFilter 一直在跑却什么都模糊不到。
  //
  // 改成 Stack 之后列表铺满整个高度，用 padding 让开两条栏的位置，
  // 滚动时内容就真的从栏下穿过，模糊才看得见。
  // 而 padding 必须等于栏的实际高度，所以这里量一次。
  final GlobalKey _headerKey = GlobalKey();
  final GlobalKey _composerKey = GlobalKey();
  double _headerH = 0;
  double _composerH = 0;

  void _measureBars() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final double h = (_headerKey.currentContext?.findRenderObject()
                  as RenderBox?)
              ?.size
              .height ??
          0;
      final double c = (_composerKey.currentContext?.findRenderObject()
                  as RenderBox?)
              ?.size
              .height ??
          0;
      // 只在真的变了才 setState，否则会无限重建
      if ((h - _headerH).abs() > 0.5 || (c - _composerH).abs() > 0.5) {
        setState(() {
          _headerH = h;
          _composerH = c;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Conversation conv = _conv;
    _measureBars();

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkBg
          : AppColors.lightBg,
      // 用 Stack 而不是 Column：列表要**铺满整个高度**并从两条栏下面穿过，
      // 否则玻璃模糊没有作用对象（详见 _measureBars 的注释）。
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: _messageList(conv, topInset: _headerH, bottomInset: _composerH),
          ),
          // 往上翻看历史时，一键跳回最新消息
          if (!_atBottom)
            Positioned(
              right: 16,
              bottom: _composerH + 14,
              child: GlassIconButton(
                icon: Icons.arrow_downward_rounded,
                tooltip: '回到底部',
                size: 38,
                iconSize: 19,
                onTap: _scrollToEnd,
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: KeyedSubtree(key: _headerKey, child: _header()),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: KeyedSubtree(key: _composerKey, child: _composer()),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final AppSurface s = AppSurface.of(context);
    // 顶部安全区内边距交给 GlassBar 自己承担，而不是在外面套 SafeArea。
    // 这样玻璃背景能一直铺到屏幕顶端、延伸到状态栏后面，
    // 顶部不会留出一条割裂的纯色带。
    final double topInset = MediaQuery.of(context).padding.top;

    // 当前对话名。还没起名的会话（刚建、没发过消息）显示「新对话」。
    final String title = _conv.title.trim().isEmpty ? '新对话' : _conv.title;

    return GlassBar(
      hairlineBottom: true,
      padding: EdgeInsets.fromLTRB(18, topInset + 8, 12, 10),
      child: Row(
        children: <Widget>[
          // ---- 标题 = 当前对话名，点一下打开历史记录 ----
          //
          // 原来这一行放的是品牌名「PrivTasker」，对话名挤在下面一行 11.5px 的灰字里。
          // 两处都不对：
          //   · 品牌名在**自己的应用里**是冗余信息 —— 用户不会忘了自己开的是哪个 app，
          //     而它占掉的恰恰是头部最显眼的位置。
          //   · 多会话场景下真正需要一眼确认的是「我在哪个对话里」。那是身份信息，
          //     不该由一行小灰字来承担。
          //
          // 历史记录的入口一并并进这一行：它要表达的就是「这些对话之间可以切换」，
          // 语义上本来就属于标题。合并之后右边少一个图标按钮，
          // 头部只剩「系统权限状态 + 性能 + 设置」，清爽很多。
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Pressable(
                onTap: () =>
                    showHistorySheet(context, store: widget.conversations),
                child: Padding(
                  // 纯文字的可点区域太小，撑一点内边距到好按的尺寸
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.body(
                            // 17.5：**iOS 导航栏标题的标准字号就是 17pt**。
                            //
                            // 之前是 22 —— 那是照搬"大标题"的思路，但这块地方
                            // 不是大标题栏：它同一行里还挤着状态点、性能、设置
                            // 三个图标，标题越大越互相压。用户的原话是
                            // "聊天标题字太大了"。
                            //
                            // 17.5 而不是整 17：中文在 17pt 下略显局促，
                            // 加半个点让汉字有呼吸空间，英文也不会显得散。
                            size: 17.5,
                            weight: FontWeight.w600,
                            color: s.text,
                            height: 1.2,
                            // 字号小了，负字距也要跟着收 ——
                            // -0.3 是给 22px 配的，17.5 用它会显得挤。
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 3),
                      // 向下的箭头 =「这里点开还有东西」。
                      // 少了它，用户不会想到标题是可以点的。
                      // 跟着标题一起缩，否则箭头会比字还高。
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: s.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _shizukuDot(),
          const SizedBox(width: 2),
          // 插件入口已移进设置（头部太挤，而插件不是高频操作）；
          // 这里换成性能面板 —— 它在调试和观察用量时会被反复打开。
          GlassIconButton(
            icon: Icons.speed_rounded,
            tooltip: '性能',
            size: 36,
            iconSize: 18,
            onTap: () => showPerformanceSheet(
              context,
              settings: widget.settings,
              contextTokens: _contextTokens(),
            ),
          ),
          const SizedBox(width: 6),
          GlassIconButton(
            icon: Icons.settings_outlined,
            tooltip: '设置',
            size: 36,
            iconSize: 18,
            onTap: () => showSettingsSheet(
              context,
              settings: widget.settings,
              workDir: widget.workDir,
              plugins: widget.plugins,
              conversations: widget.conversations,
              notes: widget.notes,
              tasks: widget.tasks,
            ),
          ),
        ],
      ),
    );
  }

  Widget _shizukuDot() {
    final ShizukuService z = widget.shizuku;
    final bool ok = z.ready;

    // 未授权只是「部分功能缺失」，用橙色而不是红色，
    // 完全没装 Shizuku 才用中性灰 —— 都不该让用户以为应用坏了。
    final Color color = ok
        ? AppColors.success
        : z.supported
            ? AppColors.warning
            : AppColors.neutral;

    final String label = ok
        ? '系统权限已就绪，可以执行命令、管理应用、读写文件'
        : z.supported
            ? '尚未授予系统操作权限 · 点击去授权。\n未授权时联网、识图、普通对话仍可正常使用'
            : '未检测到 Shizuku。需要它才能执行系统命令等操作';

    return StatusDot(
      color: color,
      glow: ok,
      tooltip: label,
      onTap: () {
        if (!ok && z.supported) {
          _requestShizuku();
        } else {
          _snack(label.replaceAll('\n', ' '));
        }
      },
    );
  }

  Future<void> _requestShizuku() async {
    await widget.shizuku.requestPermission();
    if (mounted) _snack('已发起授权请求，请在系统弹窗中允许');
  }

  Widget _messageList(
    Conversation conv, {
    double topInset = 0,
    double bottomInset = 0,
  }) {
    if (conv.messages.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
        child: _emptyState(),
      );
    }

    return ListView.builder(
      controller: _scroll,
      // 上下内边距 = 两条栏的实测高度。列表本身铺满整个屏幕，
      // 靠 padding 让内容从栏下方开始 —— 这样滚动时消息会**从栏下面穿过**，
      // 玻璃的模糊才有东西可模糊。
      // 首次布局时测量值还是 0，会闪一下，但下一帧就修正了。
      padding: EdgeInsets.fromLTRB(16, topInset + 6, 16, bottomInset + 14),
      itemCount: conv.messages.length,
      itemBuilder: (BuildContext context, int i) {
        return MessageView(
          message: conv.messages[i],
          onOpenLink: _openLink,
        );
      },
    );
  }

  Future<void> _openLink(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _snack('无法打开链接：$url');
    }
  }

  /// 权限提示卡片。Shizuku 和悬浮窗共用一套版式。
  Widget _permissionCard(AppSurface s, {required bool shizuku}) {
    final bool supported = shizuku ? widget.shizuku.supported : true;

    final String title = shizuku
        ? (supported ? '尚未授予系统操作权限' : '未检测到 Shizuku')
        : '尚未授予悬浮窗权限';

    final String desc = shizuku
        // 明确说明「只是部分功能受限」，避免误以为整个应用不能用
        ? '联网搜索、图片识别、普通对话都可以正常使用。\n'
            '只有执行命令、管理应用、读写文件、改系统设置、截屏这些需要系统权限的操作暂时不可用。'
        : '开启后确认框会以系统悬浮窗显示，始终在最上层。\n'
            '不开启的话，工具把别的应用切到前台时（打开应用、跳系统设置页等），'
            '确认框会被盖住，你得先切回来才能点。';

    final String buttonLabel = shizuku ? '授予权限' : '去授权';
    final bool showButton = shizuku ? supported : true;

    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.info_outline_rounded,
                  size: 17, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppFonts.body(
                    size: 14,
                    weight: FontWeight.w600,
                    color: s.text,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            desc,
            style: AppFonts.body(size: 12.8, color: s.muted, height: 1.55),
          ),
          if (showButton) ...<Widget>[
            const SizedBox(height: 11),
            GlassButton(
              label: buttonLabel,
              icon: shizuku ? Icons.shield_outlined : Icons.picture_in_picture_alt_outlined,
              accent: true,
              onTap: () async {
                if (shizuku) {
                  await _requestShizuku();
                } else {
                  await OverlayService.requestPermission();
                  final bool v = await OverlayService.canDraw();
                  if (mounted) setState(() => _overlayGranted = v);
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyState() {
    final AppSurface s = AppSurface.of(context);
    final List<(IconData, String, String)> hints = <(IconData, String, String)>[
      (Icons.travel_explore_outlined, '联网查资料', '搜一下 DeepSeek V4 有什么新特性'),
      (Icons.image_outlined, '发图给我看', '点左下角加号，选一张图'),
      (Icons.battery_5_bar_outlined, '查电量并清缓存', '查一下手机电量，顺便清掉网易云音乐的缓存'),
      (Icons.tune_rounded, '调系统设置', '把屏幕亮度调到大概一半'),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
      children: <Widget>[
        if (!widget.shizuku.ready) _permissionCard(s, shizuku: true),
        if (widget.settings.useOverlayConfirm && _overlayGranted == false)
          _permissionCard(s, shizuku: false),
        Text(
          '可以让我做什么',
          style: AppFonts.body(
            size: 13,
            weight: FontWeight.w600,
            color: s.muted,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 10),
        ...hints.map(((IconData, String, String) h) {
          return SurfaceCard(
            margin: const EdgeInsets.only(bottom: 9),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            onTap: () {
              _input.text = h.$3;
              _input.selection = TextSelection.fromPosition(
                TextPosition(offset: _input.text.length),
              );
              setState(() {});
            },
            child: Row(
              children: <Widget>[
                Icon(h.$1, size: 19, color: AppColors.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        h.$2,
                        style: AppFonts.body(
                          size: 14,
                          weight: FontWeight.w600,
                          color: s.text,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        h.$3,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.body(
                          size: 12.5,
                          color: s.muted,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _composer() {
    final AppSurface s = AppSurface.of(context);
    final bool hasContent = _input.text.trim().isNotEmpty || _pending.isNotEmpty;

    return GlassBar(
      hairlineTop: true,
      padding: EdgeInsets.fromLTRB(
        14,
        // 上 10、下 3：**输入行整体下移**。
        //
        // 实测过的原始数值（逻辑像素，屏幕高 844）：
        //   输入框 700..746，底栏胶囊 754..838 → 两者间距 8
        //   输入框在玻璃条内：上方 8.7、下方 98（下方那 98 里 90 是给标签栏让位的）
        //
        // 反馈是"离底栏太远、到上面太近"，也就是要让输入行往下靠。
        // 上下改成 10 / 3 之后：与标签栏的可见间距 8 → 3，
        // 上方的空间 8.7 → 10.7。两边同时朝用户要的方向动了。
        10,
        14,
        // **这个 `padding.bottom` 不是系统安全区。**
        //
        // 外面那层 `Scaffold` 开了 `extendBody: true`：body 会铺满整屏
        // （好让内容从标签栏底下穿过去），但 Scaffold 同时会把 body 的
        // `MediaQuery.padding.bottom` **设成底部导航栏的高度**，
        // 让 body 自己避开它。
        //
        // 所以这一行的作用是"给标签栏让位"。删掉它输入栏就会塌到标签栏底下、
        // 两者叠在一起 —— 我试过一次，就是那个结果。
        3 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_fetchingWeb)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.7,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    '正在抓取网页内容…',
                    style: AppFonts.body(size: 12.5, color: s.muted),
                  ),
                ],
              ),
            ),
          if (_pending.isNotEmpty) _pendingRow(s),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              GlassIconButton(
                icon: Icons.add_rounded,
                tooltip: '发送图片或文件',
                size: 46,
                iconSize: 22,
                onTap: _busy ? null : _showAttachMenu,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Container(
                  // 用 ShapeDecoration + side，而不是 BoxDecoration + Border.all。
                  // Border.all 在圆角处要重新计算半径，配合非整数宽度（0.9）
                  // 在不同 DPI 下会画得上下左右粗细不一 —— 就是"输入框不对称"。
                  // Material 的 shape 描边由框架统一绘制，圆角处始终均匀。
                  decoration: ShapeDecoration(
                    color: s.surface,
                    shape: RoundedRectangleBorder(
                      // 胶囊，和两侧直径 46 的圆形按钮同一曲率。
                      // 详见 AppRadius.input 的注释 —— 这里用卡片圆角(16)
                      // 会让"圆按钮 + 方框"并排，看着就是没对齐。
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      side: BorderSide(color: s.border, width: 1),
                    ),
                  ),
                  // 单行时高度锁到 46，和两侧按钮（46）一致 ——
                  // 否则输入框约 48、按钮 46，配 CrossAxisAlignment.end
                  // 看起来就是"两个按钮没对齐"。
                  constraints: const BoxConstraints(minHeight: 46),
                  alignment: Alignment.centerLeft,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    keyboardType: TextInputType.multiline,
                    style: AppFonts.body(size: 15, color: s.text, height: 1.5),
                    // 关键：没有这个 onChanged，输入时不会重建，
                    // 发送按钮会一直停在「禁用」状态 —— 表现为必须先关掉
                    // 输入法（触发一次 MediaQuery 重建）才点得动。
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: '发消息，或让我调用工具…',
                      hintStyle:
                          AppFonts.body(size: 15, color: s.muted, height: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              _busy
                  ? GlassIconButton(
                      icon: Icons.stop_rounded,
                      tooltip: '停止',
                      size: 46,
                      iconSize: 22,
                      onTap: _stop,
                    )
                  : _sendButton(hasContent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pendingRow(AppSurface s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: SizedBox(
        height: 66,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _pending.length,
          separatorBuilder: (BuildContext _, int _) => const SizedBox(width: 8),
          itemBuilder: (BuildContext context, int i) {
            final Attachment a = _pending[i];
            return Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: s.surface,
                    borderRadius: BorderRadius.circular(AppRadius.code),
                    border: Border.all(color: s.border, width: 0.9),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: switch (a.kind) {
                    AttachmentKind.image => Image.file(
                        File(a.path),
                        fit: BoxFit.cover,
                        errorBuilder:
                            (BuildContext _, Object _, StackTrace? _) => Center(
                          child: Icon(Icons.broken_image_outlined,
                              size: 20, color: s.muted),
                        ),
                      ),
                    AttachmentKind.web => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Icon(Icons.public_rounded,
                                  size: 17, color: AppColors.accent),
                              const SizedBox(height: 4),
                              Text(
                                _hostOf(a.path),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: AppFonts.body(
                                    size: 9.5, color: s.muted, height: 1.25),
                              ),
                            ],
                          ),
                        ),
                      ),
                    AttachmentKind.file => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(
                            a.name,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: AppFonts.body(
                                size: 10.5, color: s.muted, height: 1.3),
                          ),
                        ),
                      ),
                  },
                ),
                Positioned(
                  top: -6,
                  right: -6,
                  child: GestureDetector(
                    onTap: () => setState(() => _pending.removeAt(i)),
                    child: Container(
                      width: 21,
                      height: 21,
                      decoration: const BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 13, color: Colors.white),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _hostOf(String url) {
    final Uri? u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return url;
    return u.host;
  }

  /// 发送按钮。
  ///
  /// **换成液态玻璃了。**
  ///
  /// 原来是 Material + InkWell 的实心圆（有内容时填充强调色）。它旁边那个
  /// 「停止」按钮用的是玻璃 —— 同一行里一个实心一个玻璃，看着就是没做完。
  ///
  /// 和别的按钮一样，**语义交给图标颜色**：有内容时图标是强调色，
  /// 没内容时是灰色 + 降透明度。玻璃的观感靠折射和边缘高光，
  /// 硬塞一块实心色进去反而把它盖住了。
  Widget _sendButton(bool hasContent) {
    final AppSurface s = AppSurface.of(context);
    return GlassIconButton(
      icon: Icons.arrow_upward_rounded,
      tooltip: hasContent ? '发送' : '先输入内容',
      size: 46,
      iconSize: 22,
      color: hasContent ? AppColors.accent : s.muted,
      onTap: hasContent ? _send : null,
    );
  }
}
