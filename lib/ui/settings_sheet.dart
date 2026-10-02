import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/background.dart';
import '../core/custom_font.dart';
import '../core/memory.dart';
import '../core/overlay.dart';
import '../core/productivity.dart';
import '../core/rules.dart';
import '../core/store.dart';
import '../plugins/plugin.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../tools/browser_tool.dart';
import 'backup_actions.dart';
import 'home_shell.dart';
import 'memory_page.dart';
import 'plugins_sheet.dart';
import 'python_console_page.dart';
import 'remote_page.dart';
import 'rules_page.dart';
import 'storage_sheet.dart';
import 'teenspace_page.dart';
import 'workspace_page.dart';

/// 打开设置。
///
/// **是独立页面，不是底部面板。**
///
/// 原来是 `showModalBottomSheet`。改成页面有三个理由：
/// · 设置内容很长（外观 / 接口 / 安全 / 联网 / 记忆 / 数据 / 更多），
///   面板被高度上限压着，用户得在一个"只有八成屏高"的框里翻半天。
/// · 面板随时可以被下滑手势误关，而设置里有些操作是**未保存的**
///   （滑块、输入框），关了就得重来。
/// · 页面上有明确的返回按钮，"我进了一个新地方"这件事是清楚的；
///   面板会让人不确定"我是不是还在原来的页面上"。
///
/// 名字保留 `showSettingsSheet` 是为了不动调用点 —— 但它的行为已经是
/// "push 一个页面"。下次有人看到这个名字觉得别扭，可以顺手改成
/// `openSettings`。
Future<void> showSettingsSheet(
  BuildContext context, {
  required Settings settings,
  required String workDir,
  required PluginStore plugins,
  required ConversationStore conversations,
  required NoteStore notes,
  required TaskStore tasks,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (BuildContext _) => _SettingsSheet(
        settings: settings,
        workDir: workDir,
        plugins: plugins,
        conversations: conversations,
        notes: notes,
        tasks: tasks,
      ),
    ),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({
    required this.settings,
    required this.workDir,
    required this.plugins,
    required this.conversations,
    required this.notes,
    required this.tasks,
  });

  final Settings settings;
  final String workDir;
  final PluginStore plugins;
  final ConversationStore conversations;
  final NoteStore notes;
  final TaskStore tasks;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final TextEditingController _apiKey;
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _searchKey;
  late final TextEditingController _visionUrl;
  late final TextEditingController _visionKey;
  late final TextEditingController _visionModel;

  late double _temperature;
  late int _maxRounds;
  late bool _autoApproveSafe;
  late bool _thinking;
  late String _effort;
  late String _engine;
  late String _searchMode;
  late bool _useOverlay;
  bool _showKey = false;

  /// 悬浮窗权限状态；null 表示还没查到
  bool? _canOverlay;

  @override
  void initState() {
    super.initState();

    // 探测后台保活状态（有没有加入电池优化白名单）。
    // 不 await：它是异步的系统查询，不该拖慢设置页打开。
    BackgroundService.instance.refresh().then((_) {
      if (mounted) setState(() {});
    });

    final Settings s = widget.settings;
    _apiKey = TextEditingController(text: s.apiKey);
    _baseUrl = TextEditingController(text: s.baseUrl);
    _model = TextEditingController(text: s.model);
    _searchKey = TextEditingController(text: s.searchApiKey);
    _visionUrl = TextEditingController(text: s.visionBaseUrl);
    _visionKey = TextEditingController(text: s.visionApiKey);
    _visionModel = TextEditingController(text: s.visionModel);
    _temperature = s.temperature;
    _maxRounds = s.maxToolRounds;
    _autoApproveSafe = s.autoApproveSafe;
    _thinking = s.thinkingEnabled;
    _effort = s.reasoningEffort;
    _engine = s.searchEngine;
    _searchMode = s.webSearchMode;
    _useOverlay = s.useOverlayConfirm;

    OverlayService.canDraw().then((bool v) {
      if (mounted) setState(() => _canOverlay = v);
    });
  }

  @override
  void dispose() {
    _persist();
    _apiKey.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _searchKey.dispose();
    _visionUrl.dispose();
    _visionKey.dispose();
    _visionModel.dispose();
    super.dispose();
  }

  void _persist() {
    // 退出时统一落盘，避免每敲一个字符就写一次 SharedPreferences
    widget.settings.update(() {
      widget.settings.apiKey = _apiKey.text.trim();
      widget.settings.baseUrl = _baseUrl.text.trim();
      widget.settings.model = _model.text.trim().isEmpty
          ? 'deepseek-flash'
          : _model.text.trim();
      widget.settings.searchApiKey = _searchKey.text.trim();
      widget.settings.visionBaseUrl = _visionUrl.text.trim();
      widget.settings.visionApiKey = _visionKey.text.trim();
      widget.settings.visionModel = _visionModel.text.trim();
      widget.settings.temperature = _temperature;
      widget.settings.maxToolRounds = _maxRounds;
      widget.settings.autoApproveSafe = _autoApproveSafe;
      widget.settings.thinkingEnabled = _thinking;
      widget.settings.reasoningEffort = _effort;
      widget.settings.searchEngine = _engine;
      widget.settings.webSearchMode = _searchMode;
      widget.settings.useOverlayConfirm = _useOverlay;
    });
  }

  /// 字体方案 + 字号。
  ///
  /// 三个方案**都不依赖额外字体文件**：前两个用已打包的 Times/宋体，
  /// 第三个用 Android 系统自带的族名（Flutter 会映射到系统字体，
  /// 不需要在 pubspec 里声明）。所以切换**不增加 APK 体积**。
  Widget _fontOptions(AppSurface s) {
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '字体',
            style: AppFonts.body(
              size: 13,
              weight: FontWeight.w600,
              color: s.text,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),

          // ---- 方案 ----
          for (final (String, String, String) scheme in AppFonts.schemes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.code),
                onTap: () async {
                  // 选「苹方 / 自定义字体」但还没选过文件时，**顺手把选文件
                  // 的对话框弹出来**。
                  //
                  // 不这么做的话，用户点了这一项界面**毫无变化** ——
                  // 字体文件还没加载，那个家族名不存在，Flutter 会静默回退到
                  // 系统字体。用户只会觉得"这功能是坏的"。
                  // （这正是"怎么加苹方"被问了两次的原因。）
                  if (scheme.$1 == 'custom' && !CustomFont.loaded) {
                    await _pickFontFile();
                    if (!mounted) return;
                    // 用户在选文件对话框里取消了 —— 那就别切过去，
                    // 切了也没有任何效果。
                    if (!CustomFont.loaded) return;
                  }
                  await widget.settings.update(
                    () => widget.settings.fontScheme = scheme.$1,
                  );
                  if (mounted) setState(() {});
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              scheme.$2,
                              style: AppFonts.body(
                                size: 13.5,
                                weight: FontWeight.w600,
                                color: widget.settings.fontScheme == scheme.$1
                                    ? AppColors.accent
                                    : s.text,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              scheme.$3,
                              style: AppFonts.body(
                                  size: 11.5, color: s.muted, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      if (widget.settings.fontScheme == scheme.$1)
                        Icon(Icons.check_circle_rounded,
                            size: 18, color: AppColors.accent),
                    ],
                  ),
                ),
              ),
            ),

          const SizedBox(height: 8),
          _customFontRow(s),

          const SizedBox(height: 10),
          Divider(color: s.border, height: 1),
          const SizedBox(height: 12),

          // ---- 字号 ----
          Row(
            children: <Widget>[
              Text('字号', style: AppFonts.body(size: 13, color: s.text)),
              const Spacer(),
              // 显示**最终**倍率而不是滑杆值 ——
              // 用户关心的是"实际多大"，不是"我调了多少"（那还得自己乘 1.15）
              Text(
                '${(AppFonts.baseScale * widget.settings.fontScale * 100).round()}%',
                style: AppFonts.code(size: 12, color: AppColors.accent),
              ),
            ],
          ),
          Slider(
            value: widget.settings.fontScale,
            min: 0.85,
            max: 1.4,
            divisions: 11,
            label:
                '${(AppFonts.baseScale * widget.settings.fontScale * 100).round()}%',
            onChanged: (double v) =>
                widget.settings.update(() => widget.settings.fontScale = v),
          ),
          Text(
            '所有文字（正文、代码块、表格）会一起缩放。'
            '刻意不用系统的字体大小设置 —— markdown 走 RichText，'
            '它不响应那个设置，会导致正文放大而代码块没放大。',
            style: AppFonts.body(size: 11, color: s.muted, height: 1.5),
          ),
        ],
      ),
    );
  }

  /// 自定义字体文件（苹方等）。
  ///
  /// **为什么是"选文件"而不是把苹方打进包里：**
  /// 苹方是苹果的系统字体，不能随仓库分发；更硬的一条是 Flutter 不支持
  /// "可选字体资源" —— 写进 `pubspec.yaml` 却在打包时找不到文件会**直接让
  /// 构建失败**，于是任何没有这个字体的人都编译不过去。
  /// 详细的取舍见 `core/custom_font.dart` 的注释。
  Widget _customFontRow(AppSurface s) {
    final bool active = widget.settings.fontScheme == 'custom';
    final bool loaded = CustomFont.loaded;
    final String? err = CustomFont.error;

    return Container(
      decoration: BoxDecoration(
        color: s.codeBg,
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  loaded ? CustomFont.fileName : '未选择字体文件',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.body(
                    size: 12.8,
                    weight: FontWeight.w600,
                    color: s.text,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  err ??
                      (loaded
                          ? (active ? '正在使用' : '已加载。选「苹方 / 自定义字体」后生效')
                          : '选一个字体文件（苹方、思源等）。'
                              '苹方是苹果的系统字体，不能随应用分发，'
                              '所以要从你手机里的文件选。'),
                  style: AppFonts.body(
                    size: 11.2,
                    color: err != null ? AppColors.danger : s.muted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GlassButton(
            label: loaded ? '更换' : '选择',
            fontSize: 12.5,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            onTap: _pickFontFile,
          ),
          if (loaded) ...<Widget>[
            const SizedBox(width: 6),
            GlassButton(
              label: '清除',
              fontSize: 12.5,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              onTap: () async {
                await widget.settings.update(() {
                  CustomFont.clear();
                  widget.settings.customFontPath = '';
                  // 自定义字体没了，还停在这个方案上就会回退成系统字体 ——
                  // 与其让用户对着一个"没效果"的选项，不如切回默认方案。
                  if (widget.settings.fontScheme == 'custom') {
                    widget.settings.fontScheme = 'sans';
                  }
                });
                if (mounted) setState(() {});
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickFontFile() async {
    const XTypeGroup group = XTypeGroup(
      label: '字体',
      extensions: <String>['ttf', 'otf', 'ttc'],
    );
    final XFile? f = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
    if (f == null) return;

    final String? err = await CustomFont.loadFrom(f.path);

    await widget.settings.update(() {
      widget.settings.customFontPath = err == null ? f.path : '';
      // 选成功就顺手切过去 —— 用户挑字体文件的目的就是要用它，
      // 再让他回去点一下"自定义字体"是多余的步骤。
      if (err == null) widget.settings.fontScheme = 'custom';
    });

    if (mounted) setState(() {});
  }

  /// 图标 + 标题 + 说明 + 右箭头的可点条目
  Widget _entryCard(
    AppSurface s, {
    required IconData icon,
    required String title,
    required String desc,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        onTap: onTap,
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18, color: AppColors.accent),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: AppFonts.body(
                      size: 14,
                      weight: FontWeight.w600,
                      color: s.text,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  mdText(
                    desc,
                    style:
                        AppFonts.body(size: 12, color: s.muted, height: 1.45),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: s.muted),
          ],
        ),
      ),
    );
  }

  /// 后台保活：前台服务 + 电池优化白名单。
  ///
  /// 两件事放一张卡里，因为它们是**互补**的：
  /// 前台服务挡内存回收，白名单挡 Doze 挂起 CPU。
  /// 分开说用户会以为做一件就够了。
  Widget _bgCard(AppSurface s) {
    final BgStatus st = BackgroundService.instance.status;
    final bool ok = st.batteryIgnored;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  ok ? Icons.battery_saver_rounded : Icons.battery_alert_outlined,
                  size: 18,
                  color: ok ? AppColors.success : AppColors.warning,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '后台保活',
                    style: AppFonts.body(
                      size: 14,
                      weight: FontWeight.w600,
                      color: s.text,
                      height: 1.3,
                    ),
                  ),
                ),
                Text(
                  ok ? '已加入白名单' : '未加入',
                  style: AppFonts.body(
                    size: 12,
                    color: ok ? AppColors.success : AppColors.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            mdText(
              // 说清"两件事"和"仍不保证"，否则用户会以为开了就一定跑完
              '前台服务挡得住内存回收，但挡不住 Doze（打盹时挂起 CPU、断网），'
              '所以还需要把它加入电池优化白名单。\n\n'
              '⚠️ 部分国产 ROM 有更激进的省电策略，做这两件事**显著提高**长任务存活率，'
              '但不保证一定跑完 —— 所以长任务（编译等）仍建议把输出写进日志文件，'
              '之后回来读，而不是挂着干等。',
              style: AppFonts.body(size: 11.5, color: s.muted, height: 1.6),
            ),
            if (!ok) ...<Widget>[
              const SizedBox(height: 10),
              GlassButton(
                label: '去申请（跳系统弹窗）',
                icon: Icons.open_in_new_rounded,
                fontSize: 12.5,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                onTap: () async {
                  await BackgroundService.instance.requestBattery();
                  // 用户可能在系统弹窗里操作完才回来，延迟一点再刷新，
                  // 免得刚跳过去就查、拿到还是旧状态
                  await Future<void>.delayed(const Duration(seconds: 1));
                  await BackgroundService.instance.refresh();
                  if (mounted) setState(() {});
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 悬浮窗确认开关 + 权限状态
  Widget _overlayRow(AppSurface s) {
    final bool granted = _canOverlay == true;
    final bool unknown = _canOverlay == null;

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '悬浮窗确认',
                      style: AppFonts.body(
                        size: 14,
                        weight: FontWeight.w600,
                        color: s.text,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '工具经常会把别的应用切到前台（打开应用、跳系统设置页等），'
                      '这时应用内弹窗会被盖住，你必须切回来才能点确认。'
                      '开启后改用系统悬浮窗，它始终在最上层。',
                      style: AppFonts.body(
                          size: 12.3, color: s.muted, height: 1.5),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _useOverlay,
                onChanged: (bool v) => setState(() => _useOverlay = v),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Icon(
                granted
                    ? Icons.check_circle_rounded
                    : Icons.info_outline_rounded,
                size: 15,
                color: granted ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  unknown
                      ? '正在检查权限…'
                      : granted
                          ? '已获得「显示在其他应用上层」权限'
                          : '尚未获得悬浮窗权限，目前会退回应用内弹窗',
                  style: AppFonts.body(
                    size: 12.2,
                    color: granted ? AppColors.success : s.muted,
                    height: 1.45,
                  ),
                ),
              ),
              if (!granted && !unknown)
                GlassButton(
                  label: '去授权',
                  accent: true,
                  fontSize: 12.5,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  onTap: () async {
                    await OverlayService.requestPermission();
                    // 用户从系统设置页回来后重新查一次
                    final bool v = await OverlayService.canDraw();
                    if (mounted) setState(() => _canOverlay = v);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);

    return Scaffold(
      backgroundColor: s.isDark ? AppColors.darkBg : AppColors.lightBg,
      body: Column(
        children: <Widget>[
          // 页头用和笔记/任务页同一个 AppHeader —— 三个页面的头部样式
          // 必须完全一致，否则"设置"看起来像另一个应用。
          AppHeader(
            title: '设置',
            leading: GlassIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              tooltip: '返回',
              size: 38,
              iconSize: 19,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          Expanded(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                children: <Widget>[
                  _section(s, '外观'),
                  // 主题色（种子色）选择器已删除 —— 见 AppColors.accent 的注释。
                  _fontOptions(s),

                  _section(s, '接口与模型'),
                  _field(
                    s,
                    label: 'API Key',
                    controller: _apiKey,
                    hint: 'sk-…',
                    obscure: !_showKey,
                    suffix: IconButton(
                      icon: Icon(
                        _showKey
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: s.muted,
                      ),
                      onPressed: () => setState(() => _showKey = !_showKey),
                    ),
                  ),
                  _field(
                    s,
                    label: '接口地址',
                    controller: _baseUrl,
                    hint: 'https://api.deepseek.com',
                  ),

                  // 模型并入「接口与模型」
                  ...Settings.modelPresets.map(((String, String) m) {
                    final bool active = _model.text.trim() == m.$1;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SurfaceCard(
                        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                        borderColor: active ? AppColors.accent : null,
                        onTap: () => setState(() {
                          _model.text = m.$1;
                          // 切到不支持图像的模型时给个提示（在识图小节里说明）
                        }),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    m.$1,
                                    style: AppFonts.code(
                                      size: 13.5,
                                      weight: FontWeight.w600,
                                      color: s.text,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    m.$2,
                                    style: AppFonts.body(
                                      size: 12.2,
                                      color: s.muted,
                                      height: 1.4,
                                    ),
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
                  _field(
                    s,
                    label: '模型名（也可手动填其它）',
                    controller: _model,
                    hint: 'deepseek-flash',
                  ),

                  // 思考模式并入「接口与模型」—— 它也是"怎么用模型"的一部分，
                  // 单独一节会让设置页看起来比实际复杂
                  _switchRow(
                    s,
                    label: '开启思考模式',
                    desc: '模型先输出一段思维链再作答。DeepSeek 默认开启。'
                        '注意：思考模式下 temperature、presence_penalty、'
                        'frequency_penalty 均不生效（官方说明「设置不报错但也不生效」）。',
                    value: _thinking,
                    onChanged: (bool v) => setState(() => _thinking = v),
                  ),
                  if (_thinking) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      '推理强度',
                      style: AppFonts.body(
                          size: 12.8, color: s.muted, height: 1.3),
                    ),
                    const SizedBox(height: 8),
                    ...Settings.effortPresets.map(((String, String) e) {
                      final bool active = _effort == e.$1;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SurfaceCard(
                          padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
                          borderColor: active ? AppColors.accent : null,
                          onTap: () => setState(() => _effort = e.$1),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  e.$2,
                                  style: AppFonts.body(
                                    size: 13,
                                    color: s.text,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                              Text(
                                e.$1,
                                style: AppFonts.code(
                                  size: 12,
                                  color: s.muted,
                                ),
                              ),
                              if (active) ...<Widget>[
                                const SizedBox(width: 8),
                                Icon(Icons.check_circle_rounded,
                                    size: 17, color: AppColors.accent),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                    Text(
                      '官方映射：minimal/low → low，medium/high/xhigh → high，max/ultra → max。',
                      style: AppFonts.body(
                          size: 11.6, color: s.muted, height: 1.5),
                    ),
                  ],

                  const SizedBox(height: 14),
                  _slider(
                    s,
                    label: '温度${_thinking ? '（思考模式下不生效）' : ''}',
                    value: _temperature,
                    min: 0,
                    max: 2,
                    divisions: 20,
                    display: _temperature.toStringAsFixed(1),
                    enabled: !_thinking,
                    onChanged: (double v) => setState(() => _temperature = v),
                  ),
                  _slider(
                    s,
                    label: '单轮最多工具调用次数',
                    value: _maxRounds.toDouble(),
                    min: 1,
                    max: 20,
                    divisions: 19,
                    display: '$_maxRounds 次',
                    onChanged: (double v) =>
                        setState(() => _maxRounds = v.round()),
                  ),

                  _section(s, '安全'),
                  _bgCard(s),
                  _switchRow(
                    s,
                    label: '只读命令自动执行',
                    desc: '关闭后每一条命令都需要你确认。'
                        '危险操作（卸载、清除数据、删除文件等）始终会弹窗确认，不受此项影响。',
                    value: _autoApproveSafe,
                    onChanged: (bool v) => setState(() => _autoApproveSafe = v),
                  ),
                  // 这里原来有个 `SizedBox(height: 10)`。`_switchRow` 现在
                  // 自带 9 的下间距，再补一个就变成 19 —— 比别处都宽。
                  _overlayRow(s),

                  _section(s, '联网与识图'),
                  _note(
                    s,
                    '搜索会按下列顺序尝试，直到拿到结果：\n'
                    '1. Tavily API Key —— 通用网页搜索，结果完整稳定。'
                    '填了 Key 才走这条。\n'
                    '2. Bing 直连 —— 普通 HTTP 请求，最快，不需要任何配置。\n'
                    '3. 内置浏览器抓取 —— 用 WebView 打开搜索引擎，'
                    '真实浏览器环境，用于需要 JS 渲染的页面。\n'
                    '另外 fetch 抓取指定网址任何时候都能用。',
                  ),
                  Text(
                    '联网方式',
                    style: AppFonts.body(
                        size: 12.8, color: s.muted, height: 1.3),
                  ),
                  const SizedBox(height: 8),
                  ...Settings.searchModePresets.map(((String, String) m) {
                    final bool active = _searchMode == m.$1;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SurfaceCard(
                        padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
                        borderColor: active ? AppColors.accent : null,
                        onTap: () => setState(() => _searchMode = m.$1),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                m.$2,
                                style: AppFonts.body(
                                  size: 13,
                                  color: s.text,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            if (active)
                              Icon(Icons.check_circle_rounded,
                                  size: 17, color: AppColors.accent),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 6),
                  Text(
                    '浏览器抓取使用的搜索引擎',
                    style: AppFonts.body(
                        size: 12.8, color: s.muted, height: 1.3),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: SearchEngine.all.map((SearchEngine e) {
                      final bool active = _engine == e.id;
                      return SurfaceCard(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        borderColor: active ? AppColors.accent : null,
                        onTap: () => setState(() => _engine = e.id),
                        child: Text(
                          e.label,
                          style: AppFonts.body(
                            size: 13,
                            weight: FontWeight.w600,
                            color: active ? AppColors.accent : s.text,
                            height: 1.2,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  _field(
                    s,
                    label: 'Tavily API Key（可选）',
                    controller: _searchKey,
                    hint: '填了会优先用 Tavily，结果更完整',
                  ),

                  // 识图并入「联网与识图」—— 视觉模型同样是"选一个外部服务"
                  _note(
                    s,
                    'deepseek-flash 本身支持图像理解，识图默认就走它，不需要额外配置。'
                    '识图流程：screen_capture 截图 → read_image 把图片交给模型。'
                    '注意 deepseek-v4-pro 不支持图像输入，选它时识图会降级为本地 OCR。',
                  ),
                  _field(
                    s,
                    label: '视觉接口地址（可选，覆盖上方模型）',
                    controller: _visionUrl,
                    hint: '留空则使用上面的 deepseek-flash',
                  ),
                  _field(
                    s,
                    label: '视觉 API Key（可选）',
                    controller: _visionKey,
                    hint: '留空则复用上面的 DeepSeek Key',
                    obscure: true,
                  ),
                  _field(
                    s,
                    label: '视觉模型（可选）',
                    controller: _visionModel,
                    hint: 'deepseek-flash',
                  ),

                  _section(s, '记忆'),
                  _note(
                    s,
                    'Agent 会自己判断哪些是"会长期有效的事实"并记下来'
                    '（你住在哪、习惯用什么工具、偏好什么风格），每轮对话都会带上。\n'
                    '开关关掉只是**不再带上**，条目仍然留着 —— 想真正删掉就进'
                    '「管理记忆」。这两件事分开是有意的：不然你会不敢碰这个开关。',
                  ),
                  _switchRow(
                    s,
                    label: '启用记忆',
                    desc: '关闭后记忆不再注入对话，但不会被删除',
                    value: widget.settings.memoryEnabled,
                    onChanged: (bool v) async {
                      await widget.settings
                          .update(() => widget.settings.memoryEnabled = v);
                      if (mounted) setState(() {});
                    },
                  ),
                  _entryCard(
                    s,
                    icon: Icons.psychology_outlined,
                    title: '管理记忆',
                    desc: '查看记住了什么、逐条删除、清空全部',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext _) =>
                            MemoryPage(store: MemoryStore.instance),
                      ),
                    ),
                  ),

                  _section(s, '数据与扩展'),
                  _entryCard(
                    s,
                    icon: Icons.rule_folder_outlined,
                    title: '自定义规则',
                    desc: '当……的时候，就…… —— 用自己的话规定 Agent 的行为',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext _) =>
                            RulesPage(store: RuleStore.instance),
                      ),
                    ),
                  ),
                  _entryCard(
                    s,
                    icon: Icons.terminal_rounded,
                    title: 'Python 控制台',
                    desc: '内嵌 CPython 3.13，零配置。在这里直接跑代码验证它是否可用',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext _) => const PythonConsolePage(),
                      ),
                    ),
                  ),
                  _entryCard(
                    s,
                    icon: Icons.extension_outlined,
                    title: '插件',
                    desc: '自定义工具：声明参数和命令模板，给 Agent 加能力',
                    onTap: () => showPluginsSheet(
                      context,
                      store: widget.plugins,
                      builtinNames: <String>{
                        'run_shell',
                        'app_manage',
                        'file_op',
                        'system_settings',
                        'screen_capture',
                        'web',
                        'browser',
                        'read_image',
                        'notes',
                        'tasks',
                      },
                    ),
                  ),
                  _entryCard(
                    s,
                    icon: Icons.ios_share_rounded,
                    title: '导出备份',
                    desc: '会话、笔记、任务、插件和设置（API Key 默认不含）',
                    onTap: () async {
                      final String? msg = await BackupActions.export(
                        context,
                        settings: widget.settings,
                        conversations: widget.conversations,
                        notes: widget.notes,
                        tasks: widget.tasks,
                        plugins: widget.plugins,
                      );
                      if (msg != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(msg),
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      }
                    },
                  ),
                  _entryCard(
                    s,
                    icon: Icons.download_rounded,
                    title: '导入备份',
                    desc: '从 JSON 备份恢复，可选合并或覆盖',
                    onTap: () async {
                      final String? msg = await BackupActions.import(
                        context,
                        settings: widget.settings,
                        conversations: widget.conversations,
                        notes: widget.notes,
                        tasks: widget.tasks,
                        plugins: widget.plugins,
                      );
                      if (msg != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(msg),
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      }
                    },
                  ),

                  // 存储并入「数据与扩展」—— 插件、导入导出、存储清理
                  // 都是"数据从哪来、往哪去"，归到一起更好找
                  SurfaceCard(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    onTap: () => showStorageSheet(
                      context,
                      workDir: widget.workDir,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.folder_outlined,
                            size: 18, color: AppColors.accent),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '管理存储空间',
                                style: AppFonts.body(
                                  size: 14,
                                  weight: FontWeight.w600,
                                  color: s.text,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '查看并清理截图、录屏和聊天附件',
                                style: AppFonts.body(
                                    size: 12, color: s.muted, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            size: 20, color: s.muted),
                      ],
                    ),
                  ),
                  _section(s, '更多'),
                  _entryCard(
                    s,
                    icon: Icons.desktop_windows_outlined,
                    title: '远程控制',
                    desc: '从电脑浏览器操作这台手机 —— **尚未实现**，先占位',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext _) => const RemotePage(),
                      ),
                    ),
                  ),
                  _entryCard(
                    s,
                    icon: Icons.shield_moon_outlined,
                    title: 'TeenSpace',
                    desc: '成人内容 / 政治议题 / 题目查询的回答尺度',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext _) =>
                            TeenSpacePage(settings: widget.settings),
                      ),
                    ),
                  ),
                  _entryCard(
                    s,
                    icon: Icons.workspaces_outline,
                    title: '工作空间',
                    desc: widget.settings.workspacePath.trim().isEmpty
                        ? '截图、录屏、附件的存放位置 · 当前用默认'
                        : '截图、录屏、附件的存放位置 · 当前是自定义目录',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext _) => WorkspacePage(
                          settings: widget.settings,
                          defaultWorkDir: widget.workDir,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
          ),
        ],
      ),
    );
  }

  Widget _section(AppSurface s, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        title,
        style: AppFonts.body(
          size: 12.5,
          weight: FontWeight.w600,
          color: s.muted,
          height: 1.2,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _field(
    AppSurface s, {
    required String label,
    required TextEditingController controller,
    String? hint,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: AppFonts.body(size: 12.8, color: s.muted, height: 1.3),
          ),
          const SizedBox(height: 5),
          Container(
            decoration: BoxDecoration(
              color: s.surface,
              // 胶囊，和聊天页的输入框、以及所有按钮统一。
              // 它是个普通 Container，不存在 OutlineInputBorder 在
              // 大圆角处描边畸变的问题，所以可以直接拉到最大。
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: s.border, width: 0.9),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: controller,
                    obscureText: obscure,
                    style: AppFonts.body(size: 14, color: s.text, height: 1.4),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      hintText: hint,
                      hintStyle: AppFonts.body(size: 13.5, color: s.muted),
                    ),
                  ),
                ),
                ?suffix,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(
    AppSurface s, {
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    style: AppFonts.body(size: 12.8, color: s.muted, height: 1.3),
                  ),
                ),
                Text(
                  display,
                  style: AppFonts.code(size: 12.5, color: s.text),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: AppColors.accent,
                inactiveTrackColor: s.border,
                thumbColor: AppColors.accent,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: enabled ? onChanged : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switchRow(
    AppSurface s, {
    required String label,
    required String desc,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SurfaceCard(
      // **自带下间距。**
      //
      // 原来没有，于是它和紧跟在后面的那个条目卡**贴在一起** ——
      // 设置里的「启用记忆」开关和「管理记忆」看起来是一块，
      // 分不清哪个是开关哪个是入口。
      //
      // 放在这里而不是在每个调用点补 SizedBox：全项目有 3 处开关行，
      // 漏一处就是一处贴在一起，而这种"只有某个地方挤在一起"最难看。
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
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
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: AppFonts.body(size: 12.3, color: s.muted, height: 1.5),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _note(AppSurface s, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.code),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.25),
            width: 0.8,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.info_outline_rounded,
                  size: 16, color: AppColors.accent),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: mdText(
                text,
                style: AppFonts.body(size: 12.4, color: s.text, height: 1.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
