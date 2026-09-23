import 'package:flutter/material.dart';

import '../core/rules.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';

/// 自定义规则页：**当 XXX 的时候，就 YYY**。
class RulesPage extends StatefulWidget {
  const RulesPage({super.key, required this.store});

  final RuleStore store;

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
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

    return Scaffold(
      backgroundColor: s.isDark ? AppColors.darkBg : AppColors.lightBg,
      body: Column(
        children: <Widget>[
          _header(s),
          Expanded(
            child: widget.store.rules.isEmpty
                ? _empty(s)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: <Widget>[
                      ...widget.store.rules.map((CustomRule r) => _card(s, r)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header(AppSurface s) {
    final double top = MediaQuery.of(context).padding.top;
    return GlassBar(
      hairlineBottom: true,
      padding: EdgeInsets.fromLTRB(8, top + 6, 12, 10),
      child: Row(
        children: <Widget>[
          GlassIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: '返回',
            size: 38,
            iconSize: 19,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '自定义规则',
              style: AppFonts.body(
                size: 17,
                weight: FontWeight.w700,
                color: s.text,
                height: 1.2,
              ),
            ),
          ),
          GlassIconButton(
            icon: Icons.add_rounded,
            tooltip: '新建规则',
            size: 38,
            iconSize: 19,
            onTap: () => _edit(null),
          ),
        ],
      ),
    );
  }

  Widget _empty(AppSurface s) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
      children: <Widget>[
        Icon(Icons.rule_folder_outlined,
            size: 38, color: s.muted.withValues(alpha: 0.5)),
        const SizedBox(height: 14),
        Text(
          '还没有规则',
          textAlign: TextAlign.center,
          style: AppFonts.body(
            size: 15,
            weight: FontWeight.w600,
            color: s.text,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '规则就是一句话：**当……的时候，就……**\n\n'
          '例如：\n'
          '· 当我问天气时，先用 web 查我所在城市再回答\n'
          '· 当我发英文时，先翻译成中文再回答\n'
          '· 回答技术问题时，代码块要带注释\n\n'
          '规则会在**每次对话**里生效。',
          style: AppFonts.body(size: 13, color: s.muted, height: 1.7),
        ),
        const SizedBox(height: 20),
        Center(
          child: GlassButton(
            label: '新建规则',
            icon: Icons.add_rounded,
            accent: true,
            onTap: () => _edit(null),
          ),
        ),
      ],
    );
  }

  Widget _card(AppSurface s, CustomRule r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(13, 11, 8, 11),
        onTap: () => _edit(r),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 开关：规则可以留着但临时关掉，
            // 比"删了再重建"实用得多
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Switch(
                value: r.enabled,
                onChanged: (bool v) => widget.store.toggle(r, v),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  RichText(
                    text: TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: '当 ',
                          style: AppFonts.body(
                            size: 13,
                            color: s.muted,
                            height: 1.45,
                          ),
                        ),
                        TextSpan(
                          text: r.when_,
                          style: AppFonts.body(
                            size: 13,
                            weight: FontWeight.w600,
                            color: s.text,
                            height: 1.45,
                          ),
                        ),
                        TextSpan(
                          text: ' 时，就 ',
                          style: AppFonts.body(
                            size: 13,
                            color: s.muted,
                            height: 1.45,
                          ),
                        ),
                        TextSpan(
                          text: r.then_,
                          style: AppFonts.body(
                            size: 13,
                            weight: FontWeight.w600,
                            color: AppColors.accent,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            GlassIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: '删除',
              size: 32,
              iconSize: 16,
              color: AppColors.danger,
              onTap: () => widget.store.remove(r.id),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(CustomRule? existing) async {
    final TextEditingController whenC =
        TextEditingController(text: existing?.when_ ?? '');
    final TextEditingController thenC =
        TextEditingController(text: existing?.then_ ?? '');
    final AppSurface s = AppSurface.of(context);

    final bool? ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: s.isDark ? AppColors.darkBg : AppColors.lightBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: s.border, width: 0.8)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                existing == null ? '新建规则' : '编辑规则',
                style: AppFonts.body(
                  size: 17,
                  weight: FontWeight.w700,
                  color: s.text,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 14),
              _label(s, '当……的时候'),
              const SizedBox(height: 6),
              _input(s, whenC, '例如：我让你查资料时'),
              const SizedBox(height: 14),
              _label(s, '就……'),
              const SizedBox(height: 6),
              _input(s, thenC, '例如：先列出三个来源再总结', maxLines: 3),
              const SizedBox(height: 10),
              Text(
                '用大白话写就行，模型能理解。\n'
                '规则只在**对话时**生效 —— 应用没打开时不会自己触发。',
                style: AppFonts.body(size: 11.5, color: s.muted, height: 1.6),
              ),
              const SizedBox(height: 16),
              GlassButton(
                label: '保存',
                accent: true,
                expand: true,
                onTap: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok == true) {
      final String w = whenC.text.trim();
      final String t = thenC.text.trim();
      if (w.isNotEmpty && t.isNotEmpty) {
        if (existing == null) {
          widget.store.add(w, t);
        } else {
          existing.when_ = w;
          existing.then_ = t;
          widget.store.update(existing);
        }
      }
    }

    whenC.dispose();
    thenC.dispose();
  }

  Widget _label(AppSurface s, String text) => Text(
        text,
        style: AppFonts.body(
          size: 12.5,
          weight: FontWeight.w600,
          color: s.muted,
          height: 1.3,
        ),
      );

  Widget _input(
    AppSurface s,
    TextEditingController c,
    String hint, {
    int maxLines = 1,
  }) {
    return Container(
      decoration: ShapeDecoration(
        color: s.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          side: BorderSide(color: s.border, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        style: AppFonts.body(size: 14, color: s.text, height: 1.5),
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 11),
          hintText: hint,
          hintStyle: AppFonts.body(size: 13, color: s.muted),
        ),
      ),
    );
  }
}
