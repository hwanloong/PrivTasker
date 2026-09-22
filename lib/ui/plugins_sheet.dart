import 'package:flutter/material.dart';

import '../core/models.dart';
import '../plugins/plugin.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';

Future<void> showPluginsSheet(
  BuildContext context, {
  required PluginStore store,
  required Set<String> builtinNames,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext ctx) => _PluginsSheet(
      store: store,
      builtinNames: builtinNames,
    ),
  );
}

class _PluginsSheet extends StatefulWidget {
  const _PluginsSheet({required this.store, required this.builtinNames});

  final PluginStore store;
  final Set<String> builtinNames;

  @override
  State<_PluginsSheet> createState() => _PluginsSheetState();
}

class _PluginsSheetState extends State<_PluginsSheet> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);
    final List<CustomPlugin> list = widget.store.plugins;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: s == AppSurface.dark ? AppColors.darkBg : AppColors.lightBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: s.border, width: 0.8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
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
                Row(
                  children: <Widget>[
                    const SizedBox(width: 18),
                    Expanded(
                      child: Text(
                        '自定义插件',
                        style: AppFonts.body(
                          size: 17,
                          weight: FontWeight.w700,
                          color: s.text,
                          height: 1.2,
                        ),
                      ),
                    ),
                    GlassButton(
                      label: '新建',
                      icon: Icons.add_rounded,
                      accent: true,
                      fontSize: 13,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 8),
                      onTap: () => _openEditor(null),
                    ),
                    const SizedBox(width: 14),
                  ],
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    '插件让你不写代码就能给 Agent 加工具：声明要哪些参数、'
                    '把这些参数拼成一条 shell 命令或一个 HTTP 请求即可。'
                    '注册后模型会像调用内置工具一样调用它。',
                    style:
                        AppFonts.body(size: 12.6, color: s.muted, height: 1.6),
                  ),
                ),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 34),
                    child: Center(
                      child: Text(
                        '还没有插件',
                        style: AppFonts.body(size: 14, color: s.muted),
                      ),
                    ),
                  ),
                ...list.map((CustomPlugin p) => _tile(s, p)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(AppSurface s, CustomPlugin p) {
    final String kindLabel = p.kind == PluginKind.shell ? 'shell' : 'HTTP';
    final Color riskColor = switch (p.risk) {
      RiskLevel.safe => AppColors.success,
      RiskLevel.caution => AppColors.warning,
      RiskLevel.dangerous => AppColors.danger,
    };

    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      onTap: () => _openEditor(p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  p.title.trim().isEmpty ? p.name : p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.body(
                    size: 14.2,
                    weight: FontWeight.w600,
                    color: s.text,
                    height: 1.3,
                  ),
                ),
              ),
              Switch(
                value: p.enabled,
                onChanged: (bool v) {
                  p.enabled = v;
                  widget.store.saveQuietly();
                },
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            p.name,
            style: AppFonts.code(size: 12, color: s.muted),
          ),
          const SizedBox(height: 7),
          Row(
            children: <Widget>[
              GlassChip(label: kindLabel, dense: true, color: AppColors.accent),
              const SizedBox(width: 6),
              GlassChip(
                label: switch (p.risk) {
                  RiskLevel.safe => '只读',
                  RiskLevel.caution => '需确认',
                  RiskLevel.dangerous => '危险',
                },
                dense: true,
                color: riskColor,
              ),
              const SizedBox(width: 6),
              if (p.params.isNotEmpty)
                GlassChip(
                  label: '${p.params.length} 个参数',
                  dense: true,
                ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    size: 17, color: s.muted),
                tooltip: '删除',
                onPressed: () => _confirmDelete(p),
              ),
            ],
          ),
          if (p.template.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 7),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: s.codeBg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                p.template,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.code(size: 11.8, color: s.text),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(CustomPlugin p) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(
          '删除插件？',
          style: AppFonts.body(size: 16.5, weight: FontWeight.w700, height: 1.3),
        ),
        content: Text(
          '将删除「${p.title.trim().isEmpty ? p.name : p.title}」。',
          style: AppFonts.body(size: 13.5, height: 1.6),
        ),
        actions: <Widget>[
          GlassButton(label: '取消', onTap: () => Navigator.of(ctx).pop(false)),
          GlassButton(
            label: '删除',
            danger: true,
            onTap: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (ok == true) {
      widget.store.plugins.remove(p);
      await widget.store.saveQuietly();
    }
  }

  Future<void> _openEditor(CustomPlugin? existing) async {
    final CustomPlugin? result = await Navigator.of(context).push<CustomPlugin>(
      MaterialPageRoute<CustomPlugin>(
        fullscreenDialog: true,
        builder: (BuildContext ctx) => _PluginEditor(
          existing: existing,
          takenNames: <String>{
            ...widget.builtinNames,
            ...widget.store.plugins
                .where((CustomPlugin p) => p.id != existing?.id)
                .map((CustomPlugin p) => p.name),
          },
        ),
      ),
    );

    if (result == null) return;

    final int idx =
        widget.store.plugins.indexWhere((CustomPlugin p) => p.id == result.id);
    if (idx >= 0) {
      widget.store.plugins[idx] = result;
    } else {
      widget.store.plugins.add(result);
    }
    await widget.store.saveQuietly();
  }
}

// ---------------------------------------------------------------- 编辑器

class _PluginEditor extends StatefulWidget {
  const _PluginEditor({required this.existing, required this.takenNames});

  final CustomPlugin? existing;
  final Set<String> takenNames;

  @override
  State<_PluginEditor> createState() => _PluginEditorState();
}

class _PluginEditorState extends State<_PluginEditor> {
  late final TextEditingController _name;
  late final TextEditingController _title;
  late final TextEditingController _desc;
  late final TextEditingController _template;
  late final TextEditingController _method;
  late final TextEditingController _headers;
  late final TextEditingController _body;

  late PluginKind _kind;
  late RiskLevel _risk;
  final List<PluginParam> _params = <PluginParam>[];

  String? _error;

  @override
  void initState() {
    super.initState();
    final CustomPlugin? e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _title = TextEditingController(text: e?.title ?? '');
    _desc = TextEditingController(text: e?.description ?? '');
    _template = TextEditingController(text: e?.template ?? '');
    _method = TextEditingController(text: e?.method ?? 'GET');
    _headers = TextEditingController(
      text: (e == null || e.headers.isEmpty) ? '' : e.headers.entries
          .map((MapEntry<String, String> h) => '"${h.key}": "${h.value}"')
          .join(',\n'),
    );
    _body = TextEditingController(text: e?.body ?? '');
    _kind = e?.kind ?? PluginKind.shell;
    _risk = e?.risk ?? RiskLevel.caution;
    if (e != null) _params.addAll(e.params);
  }

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _desc.dispose();
    _template.dispose();
    _method.dispose();
    _headers.dispose();
    _body.dispose();
    super.dispose();
  }

  void _save() {
    final CustomPlugin p = CustomPlugin(
      id: widget.existing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      title: _title.text.trim(),
      description: _desc.text.trim(),
      kind: _kind,
      template: _template.text.trim(),
      method: _method.text.trim().toUpperCase(),
      headers: _parseHeaders(),
      body: _body.text,
      params: _params
          .where((PluginParam e) => e.name.trim().isNotEmpty)
          .toList(),
      risk: _risk,
      enabled: widget.existing?.enabled ?? true,
    );

    final String? err =
        validatePlugin(p, takenNames: widget.takenNames);
    if (err != null) {
      setState(() => _error = err);
      return;
    }

    Navigator.of(context).pop(p);
  }

  Map<String, String> _parseHeaders() {
    final String raw = _headers.text.trim();
    if (raw.isEmpty) return <String, String>{};
    final Map<String, String> out = <String, String>{};
    // 容忍用户写成 `"A": "b", "C": "d"` 这种片段
    for (final RegExpMatch m
        in RegExp(r'"([^"]+)"\s*:\s*"([^"]*)"').allMatches(raw)) {
      out[m.group(1)!] = m.group(2)!;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);
    final bool isShell = _kind == PluginKind.shell;

    return Scaffold(
      backgroundColor:
          s == AppSurface.dark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: s.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.existing == null ? '新建插件' : '编辑插件',
          style: AppFonts.body(
            size: 17,
            weight: FontWeight.w700,
            color: s.text,
            height: 1.2,
          ),
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: GlassButton(
                label: '保存',
                accent: true,
                fontSize: 13.5,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                onTap: _save,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
        children: <Widget>[
          if (_error != null) ...<Widget>[
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: AppColors.danger.withValues(alpha: 0.3),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.error_outline_rounded,
                      size: 16, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: AppFonts.body(
                          size: 12.6, color: AppColors.danger, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],

          _label(s, '类型'),
          Row(
            children: <Widget>[
              _kindChip(s, PluginKind.shell, 'shell 命令'),
              const SizedBox(width: 8),
              _kindChip(s, PluginKind.http, 'HTTP 请求'),
            ],
          ),
          const SizedBox(height: 18),

          _label(s, '函数名（模型调用时使用，英文）'),
          _input(s, _name, 'get_prop'),
          const SizedBox(height: 14),

          _label(s, '显示名'),
          _input(s, _title, '读取系统属性'),
          const SizedBox(height: 14),

          _label(s, '说明（会告诉模型这个工具能做什么）'),
          _input(s, _desc, '读取指定的 Android 系统属性值', maxLines: 3),
          const SizedBox(height: 14),

          _label(
            s,
            isShell
                ? '命令模板（用 {{参数名}} 占位）'
                : 'URL 模板（用 {{参数名}} 占位）',
          ),
          _input(
            s,
            _template,
            isShell ? 'getprop {{key}}' : 'https://api.example.com/v1/{{path}}',
            maxLines: 3,
            mono: true,
          ),
          const SizedBox(height: 6),
          Text(
            isShell
                ? '参数值会被自动加引号转义，不用自己处理引号。'
                : '参数值会被 URL 编码后填入。',
            style: AppFonts.body(size: 11.8, color: s.muted, height: 1.5),
          ),

          if (!isShell) ...<Widget>[
            const SizedBox(height: 14),
            _label(s, '请求方法'),
            _input(s, _method, 'GET', mono: true),
            const SizedBox(height: 14),
            _label(s, '请求头（JSON 片段，可留空）'),
            _input(s, _headers, '"Authorization": "Bearer xxx"',
                maxLines: 2, mono: true),
            const SizedBox(height: 14),
            _label(s, '请求体模板（可留空）'),
            _input(s, _body, '{"q": "{{query}}"}', maxLines: 3, mono: true),
          ],

          const SizedBox(height: 22),
          Row(
            children: <Widget>[
              Expanded(child: _label(s, '参数')),
              GlassButton(
                label: '添加参数',
                icon: Icons.add_rounded,
                fontSize: 12.5,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                onTap: () => setState(() => _params.add(PluginParam(name: ''))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_params.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '还没有参数。没有参数的插件也可以直接用。',
                style: AppFonts.body(size: 12.4, color: s.muted, height: 1.5),
              ),
            ),
          ...List<Widget>.generate(_params.length, (int i) {
            final PluginParam p = _params[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SurfaceCard(
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _inlineInput(
                            s,
                            p.name,
                            '参数名',
                            (String v) => p.name = v,
                            mono: true,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded,
                              size: 16, color: s.muted),
                          onPressed: () => setState(() => _params.removeAt(i)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _inlineInput(
                      s,
                      p.description,
                      '说明',
                      (String v) => p.description = v,
                    ),
                    const SizedBox(height: 6),
                    _inlineInput(
                      s,
                      p.defaultValue,
                      '默认值（填了则此项可省略）',
                      (String v) => p.defaultValue = v,
                      mono: true,
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 18),
          _label(s, '风险等级'),
          Row(
            children: <Widget>[
              _riskChip(s, RiskLevel.safe, '只读'),
              const SizedBox(width: 8),
              _riskChip(s, RiskLevel.caution, '需确认'),
              const SizedBox(width: 8),
              _riskChip(s, RiskLevel.dangerous, '危险'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'shell 插件即使标为「只读」，运行时仍会再跑一遍命令风险检查——'
            '如果你把模板写成了删除类命令，依然会被拦下来确认。',
            style: AppFonts.body(size: 11.8, color: s.muted, height: 1.55),
          ),
        ],
      ),
    );
  }

  Widget _kindChip(AppSurface s, PluginKind kind, String label) {
    final bool active = _kind == kind;
    return GestureDetector(
      onTap: () => setState(() => _kind = kind),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active
              ? AppColors.accent.withValues(alpha: 0.14)
              : s.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? AppColors.accent : s.border,
            width: active ? 1.2 : 0.9,
          ),
        ),
        child: Text(
          label,
          style: AppFonts.body(
            size: 13,
            weight: FontWeight.w600,
            color: active ? AppColors.accent : s.text,
            height: 1.2,
          ),
        ),
      ),
    );
  }

  Widget _riskChip(AppSurface s, RiskLevel level, String label) {
    final bool active = _risk == level;
    final Color c = switch (level) {
      RiskLevel.safe => AppColors.success,
      RiskLevel.caution => AppColors.warning,
      RiskLevel.dangerous => AppColors.danger,
    };
    return GestureDetector(
      onTap: () => setState(() => _risk = level),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: active ? c.withValues(alpha: 0.14) : s.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? c : s.border,
            width: active ? 1.2 : 0.9,
          ),
        ),
        child: Text(
          label,
          style: AppFonts.body(
            size: 12.5,
            weight: FontWeight.w600,
            color: active ? c : s.text,
            height: 1.2,
          ),
        ),
      ),
    );
  }

  Widget _label(AppSurface s, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: AppFonts.body(size: 12.6, color: s.muted, height: 1.35),
      ),
    );
  }

  Widget _input(
    AppSurface s,
    TextEditingController c,
    String hint, {
    int maxLines = 1,
    bool mono = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: s.border, width: 0.9),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        style: mono
            ? AppFonts.code(size: 13, color: s.text)
            : AppFonts.body(size: 14, color: s.text, height: 1.45),
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          hintText: hint,
          hintStyle: mono
              ? AppFonts.code(size: 12.5, color: s.muted)
              : AppFonts.body(size: 13.5, color: s.muted),
        ),
      ),
    );
  }

  Widget _inlineInput(
    AppSurface s,
    String initial,
    String hint,
    ValueChanged<String> onChanged, {
    bool mono = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: s.codeBg,
        borderRadius: BorderRadius.circular(9),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: TextFormField(
        initialValue: initial,
        onChanged: onChanged,
        style: mono
            ? AppFonts.code(size: 12.5, color: s.text)
            : AppFonts.body(size: 13.5, color: s.text, height: 1.45),
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          hintText: hint,
          hintStyle: mono
              ? AppFonts.code(size: 12, color: s.muted)
              : AppFonts.body(size: 13, color: s.muted),
        ),
      ),
    );
  }
}
