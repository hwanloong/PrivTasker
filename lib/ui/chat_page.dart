import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
          style: AppFonts.body(size: 16.5, weight: FontWeight.w700, height: 1.3),
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
          style: AppFonts.body(size: 16.5, weight: FontWeight.w700, height: 1.3),
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

  /// 思考深度的中文名。放在这里而不是模型层 —— 它是纯展示用的措辞，
  /// 和存储的值（low/high/max）分开，改文案不用动数据。
  static String _effortLabel(String effort) => switch (effort) {
        'low' => '浅（快）',
        'high' => '深（默认）',
        'max' => '最深（慢）',
        _ => effort,
      };

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

  /// 滑条档位 → 存进设置的措辞
  static String _effortSliderLabel(Settings set) =>
      switch (_effortSliderValue(set)) {
        0 => '关闭',
        1 => '浅',
        2 => '深',
        _ => '最深',
      };

  static const List<String> _effortNames = <String>[
    '关闭',
    '浅（快）',
    '深（默认）',
    '最深（慢）',
  ];

  /// 对话参数面板：思考深度 / 温度 / 工具轮数。
  ///
  /// 合成一个面板而不是三个入口 —— 它们是同一类东西（"这轮对话怎么跑"），
  /// 而且用户调整时往往是连着调几个。
  Future<void> _showParamSheet() async {
    final AppSurface s = AppSurface.of(context);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setSheet) {
          final Settings set = widget.settings;
          final int effort = _effortSliderValue(set);

          void save(void Function() mutate) {
            set.update(mutate);
            setSheet(() {});
            setState(() {}); // 让「+」菜单的描述也跟着更新
          }

          return Container(
            decoration: BoxDecoration(
              color: s.isDark ? AppColors.darkBg : AppColors.lightBg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: s.border, width: 0.8)),
            ),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: s.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '对话参数',
                  style: AppFonts.body(
                    size: 17,
                    weight: FontWeight.w700,
                    color: s.text,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 16),

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
                _paramHint(
                  s,
                  '先"想"再答，质量更好但更慢、更费 token。',
                ),

                const SizedBox(height: 14),

                // ---- 温度 ----
                _paramRow(s, '温度', set.temperature.toStringAsFixed(1)),
                Slider(
                  value: set.temperature.clamp(0.0, 2.0),
                  min: 0,
                  max: 2,
                  divisions: 20,
                  label: set.temperature.toStringAsFixed(1),
                  onChanged: (double v) =>
                      save(() => set.temperature = v),
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
                  onChanged: (double v) =>
                      save(() => set.maxToolRounds = v.round()),
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
            ),
          );
        },
      ),
    );
  }

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
      child: Text(
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

  /// 选思考深度。
  Future<void> _pickThinking() async {
    final List<(String, String)> presets = <(String, String)>[
      ('__off__', '关闭思考 · 最快，适合简单问答'),
      ('low', '浅 · 快，适合改文字、查东西'),
      ('high', '深 · 默认，日常够用'),
      ('max', '最深 · 慢，适合复杂推理和写代码'),
    ];

    final String current =
        widget.settings.thinkingEnabled ? widget.settings.reasoningEffort : '__off__';

    final String? picked = await _pickSheet(
      title: '思考深度',
      current: current,
      options: presets,
      note: '思考模式会先"想"再答，质量更好但更慢、更费 token。'
          '关闭后温度等采样参数才会生效。',
    );
    if (picked == null) return;

    await widget.settings.update(() {
      if (picked == '__off__') {
        widget.settings.thinkingEnabled = false;
      } else {
        widget.settings.thinkingEnabled = true;
        widget.settings.reasoningEffort = picked;
      }
    });
    if (mounted) setState(() {});
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
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => Container(
        decoration: BoxDecoration(
          color: s.isDark ? AppColors.darkBg : AppColors.lightBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: s.border, width: 0.8)),
        ),
        child: SafeArea(
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
                  weight: FontWeight.w700,
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
      ),
    );
  }

  void _showAttachMenu() {
    final AppSurface s = AppSurface.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => Container(
        decoration: BoxDecoration(
          color: s.isDark ? AppColors.darkBg : AppColors.lightBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: s.border, width: 0.8)),
        ),
        child: SafeArea(
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

              // ---- 会话控制（和"附件"是不同类别，所以放最上面并分隔开）----
              //
              // 模型和思考深度是**调一次就会影响整轮对话**的东西，
              // 放在设置里要翻好几层；而它们的调整时机恰恰是"发消息前"，
              // 也就是用户手指正停在「+」上的时候。
              _attachOption(
                s,
                icon: Icons.memory_rounded,
                label: '模型',
                desc: widget.settings.model,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickModel();
                },
              ),
              _attachOption(
                s,
                icon: Icons.tune_rounded,
                label: '对话参数',
                desc: '思考深度 ${_effortSliderLabel(widget.settings)} · '
                    '温度 ${widget.settings.temperature.toStringAsFixed(1)} · '
                    '最多 ${widget.settings.maxToolRounds} 轮工具',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showParamSheet();
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                child: Divider(color: s.border, height: 1),
              ),

              _attachOption(
                s,
                icon: Icons.photo_library_outlined,
                label: '从相册选图片',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
              _attachOption(
                s,
                icon: Icons.photo_camera_outlined,
                label: '拍照',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
              _attachOption(
                s,
                icon: Icons.attach_file_rounded,
                label: '选择文件',
                desc: '文本类文件会把内容读给模型',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickFile();
                },
              ),
              _attachOption(
                s,
                icon: Icons.link_rounded,
                label: '网页或接口链接',
                desc: '抓取内容后发给模型，如 Mapbox API',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _addWebLink();
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachOption(
    AppSurface s, {
    required IconData icon,
    required String label,
    String? desc,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SurfaceCard(
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
                      style: AppFonts.body(
                          size: 12, color: s.muted, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
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

    return GlassBar(
      hairlineBottom: true,
      padding: EdgeInsets.fromLTRB(18, topInset + 6, 12, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // 品牌名用**渐变文字**（方案取自定义图标同一条蓝紫渐变），
                // 所以头部和图标是同一套配色。
                GradientText(
                  text: 'PrivTasker',
                  style: AppFonts.body(
                    size: 21,
                    weight: FontWeight.w700,
                    // 这里的颜色不生效（会被 ShaderMask 的渐变盖掉），
                    // 但必须给一个不透明的值 —— 用半透明会让渐变整体变淡
                    color: Colors.black,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                // 副标题改成**当前聊天名称** ——
                // 原来那行是"模型名 · 工具已启用"，那是状态信息不是身份信息；
                // 而多会话场景下，用户最需要一眼确认的是"我在哪个对话里"。
                Text(
                  _conv.title.trim().isEmpty ? '新对话' : _conv.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.body(size: 11.5, color: s.muted, height: 1.25),
                ),
              ],
            ),
          ),
          _shizukuDot(),
          const SizedBox(width: 2),
          GlassIconButton(
            icon: Icons.history_rounded,
            tooltip: '历史记录',
            size: 36,
            iconSize: 18,
            onTap: () => showHistorySheet(context, store: widget.conversations),
          ),
          const SizedBox(width: 6),
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
              contextTokens: _conv.messages.fold<int>(
                0,
                (int sum, ChatMessage m) => sum + AppMetrics.estimate(m.content),
              ),
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
        10,
        14,
        10 + MediaQuery.of(context).padding.bottom,
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
                      borderRadius: BorderRadius.circular(AppRadius.card),
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

  Widget _sendButton(bool hasContent) {
    final AppSurface s = AppSurface.of(context);
    final ColorScheme c = Theme.of(context).colorScheme;
    return Material(
      // 用 M3 颜色角色而不是写死的常量 —— 换主题色时它要跟着变
      color: hasContent ? c.primary : s.surface,
      shape: CircleBorder(
        side: BorderSide(
          color: hasContent ? Colors.transparent : s.border,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hasContent ? _send : null,
        child: SizedBox(
          // 必须和左侧「+」按钮、以及输入框最小高度一致（都是 46），
          // 否则 CrossAxisAlignment.end 下两个按钮看起来是错位的。
          width: 46,
          height: 46,
          child: Icon(
            Icons.arrow_upward_rounded,
            size: 22,
            color: hasContent ? c.onPrimary : s.muted,
          ),
        ),
      ),
    );
  }
}
