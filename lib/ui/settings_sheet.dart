import 'package:flutter/material.dart';

import '../core/overlay.dart';
import '../core/productivity.dart';
import '../core/selfhosted_search.dart';
import '../core/store.dart';
import '../plugins/plugin.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../tools/browser_tool.dart';
import 'backup_actions.dart';
import 'plugins_sheet.dart';
import 'storage_sheet.dart';

Future<void> showSettingsSheet(
  BuildContext context, {
  required Settings settings,
  required String workDir,
  required PluginStore plugins,
  required ConversationStore conversations,
  required NoteStore notes,
  required TaskStore tasks,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext ctx) => _SettingsSheet(
      settings: settings,
      workDir: workDir,
      plugins: plugins,
      conversations: conversations,
      notes: notes,
      tasks: tasks,
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
  late final TextEditingController _selfHostedUrl;

  /// 自建搜索服务的连接测试结果
  String? _selfHostedStatus;
  bool? _selfHostedOk;
  late bool _useOverlay;
  bool _showKey = false;

  /// 悬浮窗权限状态；null 表示还没查到
  bool? _canOverlay;

  @override
  void initState() {
    super.initState();
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
    _selfHostedUrl = TextEditingController(text: s.selfHostedSearchUrl);
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
    _selfHostedUrl.dispose();
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
      widget.settings.selfHostedSearchUrl = _selfHostedUrl.text.trim();
      widget.settings.useOverlayConfirm = _useOverlay;
    });
  }

  /// 探活自建搜索服务。地址填错是最常见的失败原因，
  /// 所以给它一个能立刻验证的按钮，而不是等到搜索失败才发现。
  Future<void> _testSelfHosted() async {
    final String url = _selfHostedUrl.text.trim();
    if (url.isEmpty) {
      setState(() {
        _selfHostedOk = false;
        _selfHostedStatus = '请先填地址';
      });
      return;
    }

    setState(() {
      _selfHostedOk = null;
      _selfHostedStatus = '正在连接…';
    });

    final String? err = await SelfHostedSearch.health(url);
    if (!mounted) return;

    setState(() {
      _selfHostedOk = err == null;
      _selfHostedStatus = err == null ? '连接正常' : '连接失败：$err';
    });
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
                  Text(
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

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: BoxDecoration(
          color: s == AppSurface.dark ? AppColors.darkBg : AppColors.lightBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: s.border, width: 0.8)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _handle(s),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                children: <Widget>[
                  _section(s, '接口'),
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

                  _section(s, '模型'),
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
                              const Icon(Icons.check_circle_rounded,
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

                  _section(s, '思考模式'),
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
                                const Icon(Icons.check_circle_rounded,
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
                  _switchRow(
                    s,
                    label: '只读命令自动执行',
                    desc: '关闭后每一条命令都需要你确认。'
                        '危险操作（卸载、清除数据、删除文件等）始终会弹窗确认，不受此项影响。',
                    value: _autoApproveSafe,
                    onChanged: (bool v) => setState(() => _autoApproveSafe = v),
                  ),
                  const SizedBox(height: 10),
                  _overlayRow(s),

                  _section(s, '联网'),
                  _note(
                    s,
                    '搜索会按下列顺序尝试，直到拿到结果：\n'
                    '0. 自建搜索服务（可选）—— 自己部署的 agent-web-search 这类服务。'
                    '它替我们做完了抓取 → 正文提取 → 去噪 → 分块 → 向量化 → 相关度排序，'
                    '拿回来就是能直接读的资料，还自带提示注入清洗。质量最高，但要自己部署。\n'
                    '1. DeepSeek 服务端搜索 —— 走 Responses API 的 web_search，'
                    '不受反爬影响、也不用等渲染。\n'
                    '2. Tavily API Key —— 通用网页搜索，结果完整稳定。\n'
                    '3. 内置浏览器抓取 —— 用 WebView 打开搜索引擎，'
                    '真实浏览器环境，绕开服务端抓取被反爬拦截的问题。\n'
                    '另外 fetch 抓取指定网址任何时候都能用。',
                  ),
                  _field(
                    s,
                    label: '自建搜索服务地址（可选）',
                    controller: _selfHostedUrl,
                    hint: 'http://192.168.1.10:8000',
                  ),
                  Row(
                    children: <Widget>[
                      GlassButton(
                        label: '测试连接',
                        icon: Icons.wifi_tethering_rounded,
                        fontSize: 12.5,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        onTap: _testSelfHosted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _selfHostedStatus ?? '',
                          style: AppFonts.body(
                            size: 12,
                            color: _selfHostedOk == true
                                ? AppColors.success
                                : AppColors.danger,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
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
                              const Icon(Icons.check_circle_rounded,
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

                  _section(s, '识图'),
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

                  _section(s, '扩展'),
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

                  _section(s, '存储'),
                  SurfaceCard(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    onTap: () => showStorageSheet(
                      context,
                      workDir: widget.workDir,
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.folder_outlined,
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
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _handle(AppSurface s) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 12),
      child: Column(
        children: <Widget>[
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
            '设置',
            style: AppFonts.body(
              size: 17,
              weight: FontWeight.w700,
              color: s.text,
              height: 1.2,
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
          weight: FontWeight.w700,
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
              borderRadius: BorderRadius.circular(12),
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
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.25),
            width: 0.8,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.info_outline_rounded,
                  size: 16, color: AppColors.accent),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
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
