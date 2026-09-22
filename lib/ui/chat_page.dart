import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/agent.dart';
import '../core/metrics.dart';
import '../core/models.dart';
import '../core/overlay.dart';
import '../core/productivity.dart';
import '../core/store.dart';
import '../core/web_fetch.dart';
import '../plugins/plugin.dart';
import '../shizuku/shizuku_service.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../tools/android_tools.dart';
import '../tools/browser_tool.dart';
import '../tools/extra_tools.dart';
import '../tools/productivity_tools.dart';
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

class _ChatPageState extends State<ChatPage> {
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
                borderRadius: BorderRadius.circular(12),
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

  void _showAttachMenu() {
    final AppSurface s = AppSurface.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => Container(
        decoration: BoxDecoration(
          color: s == AppSurface.dark ? AppColors.darkBg : AppColors.lightBg,
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

    try {
      await runner.run(
        conversation: conv,
        onUpdate: () {
          if (!mounted) return;
          setState(() {});
          _scrollToEnd();
          widget.conversations.save();
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
    }
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

  @override
  Widget build(BuildContext context) {
    final Conversation conv = _conv;

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkBg
          : AppColors.lightBg,
      body: Column(
        children: <Widget>[
          _header(),
          Expanded(
            child: Stack(
              children: <Widget>[
                _messageList(conv),
                // 往上翻看历史时，一键跳回最新消息
                if (!_atBottom)
                  Positioned(
                    right: 16,
                    bottom: 14,
                    child: GlassIconButton(
                      icon: Icons.arrow_downward_rounded,
                      tooltip: '回到底部',
                      size: 38,
                      iconSize: 19,
                      onTap: _scrollToEnd,
                    ),
                  ),
              ],
            ),
          ),
          _composer(),
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
                Text(
                  'PrivTasker',
                  style: AppFonts.body(
                    size: 20,
                    weight: FontWeight.w700,
                    color: s.text,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.settings.configured
                      ? '${widget.settings.model} · 工具已启用'
                      : '未配置 API Key',
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

  Widget _messageList(Conversation conv) {
    if (conv.messages.isEmpty) {
      return _emptyState();
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
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
                  const SizedBox(
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
                size: 42,
                iconSize: 21,
                onTap: _busy ? null : _showAttachMenu,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: s.surface,
                    borderRadius: BorderRadius.circular(21),
                    border: Border.all(color: s.border, width: 0.9),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
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
                      size: 42,
                      iconSize: 21,
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
                    borderRadius: BorderRadius.circular(12),
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
                              const Icon(Icons.public_rounded,
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
    return Material(
      color: hasContent ? AppColors.accent : s.surface,
      shape: CircleBorder(
        side: BorderSide(
          color: hasContent ? Colors.transparent : s.border,
          width: 0.9,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hasContent ? _send : null,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            Icons.arrow_upward_rounded,
            size: 21,
            color: hasContent ? Colors.white : s.muted,
          ),
        ),
      ),
    );
  }
}
