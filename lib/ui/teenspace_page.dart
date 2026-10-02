import 'package:flutter/material.dart';

import '../core/store.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'home_shell.dart';

/// TeenSpace：内容尺度的三档敏感度。
///
/// ## 这一页**不是**内容过滤器
///
/// 必须先把这件事说清楚，否则它的存在本身就是误导：
///
/// · 应用**没有能力在本地判断**什么算"政治议题"、什么算 R 级 ——
///   那需要语义理解，本地只有一个 OCR。
/// · 所以这三档的真实作用是**写进系统提示词**，让模型自己按这个尺度回答。
///   也就是说它约束的是**模型的表达**，不是"拦截内容"。
/// · 绕过它的方式很直接：用户自己问别的话题、或者换个模型。
///
/// 把它做成一个看起来像"内容过滤开关"的东西，用户会以为打开就万无一失 ——
/// 那是假的，而且这种假的安全感比没有更糟。
///
/// 所以页面上直接写明它的作用边界。
class TeenSpacePage extends StatefulWidget {
  const TeenSpacePage({super.key, required this.settings});

  final Settings settings;

  @override
  State<TeenSpacePage> createState() => _TeenSpacePageState();
}

class _TeenSpacePageState extends State<TeenSpacePage> {
  static const List<String> _names = <String>['宽松', '标准', '严格'];

  static const List<(String, String, String)> _items = <(String, String, String)>[
    (
      '成人 / R 级内容',
      '包含性、暴力、血腥描写的提问与创作',
      '严格档下模型会拒绝直接描写，只给概括或建议换个方向。'
    ),
    (
      '政治议题',
      '时政评论、立场分析、敏感历史事件',
      '严格档下模型只陈述事实、不给立场判断，也不做预测。'
    ),
    (
      '题目查询',
      '作业题、考试题、竞赛题',
      '严格档下模型不直接给最终答案，而是讲思路、指出卡在哪一步。'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);

    return Scaffold(
      backgroundColor: s.isDark ? AppColors.darkBg : AppColors.lightBg,
      body: Column(
        children: <Widget>[
          AppHeader(
            title: 'TeenSpace',
            subtitle: '内容尺度的敏感度',
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
              children: <Widget>[
                SurfaceCard(
                  color: AppColors.warning.withValues(alpha: 0.10),
                  borderColor: AppColors.warning.withValues(alpha: 0.30),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(Icons.info_outline_rounded,
                          size: 18, color: AppColors.warning),
                      const SizedBox(width: 10),
                      Expanded(
                        child: mdText(
                          '**这不是内容过滤器。**\n'
                          '本地没有语义理解能力，判断不了"什么算政治议题"。'
                          '这三档是写进系统提示词里的**回答尺度**，'
                          '约束的是模型的表达方式，不是拦截内容。',
                          style: AppFonts.body(
                              size: 13, color: s.text, height: 1.6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _slider(s, 0, widget.settings.teenAdult,
                    (int v) => widget.settings.update(() => widget.settings.teenAdult = v)),
                const SizedBox(height: 6),
                _slider(s, 1, widget.settings.teenPolitics,
                    (int v) => widget.settings.update(() => widget.settings.teenPolitics = v)),
                const SizedBox(height: 6),
                _slider(s, 2, widget.settings.teenQuery,
                    (int v) => widget.settings.update(() => widget.settings.teenQuery = v)),

                const SizedBox(height: 18),
                Text(
                  '三档分别是什么意思',
                  style: AppFonts.body(
                      size: 13.5, weight: FontWeight.w600, color: s.text),
                ),
                const SizedBox(height: 8),
                for (final (String title, String what, String strict) in _items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SurfaceCard(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            title,
                            style: AppFonts.body(
                                size: 13.5,
                                weight: FontWeight.w600,
                                color: s.text,
                                height: 1.3),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            what,
                            style: AppFonts.body(
                                size: 12, color: s.muted, height: 1.5),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            strict,
                            style: AppFonts.body(
                                size: 12, color: s.muted, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 8),
                Text(
                  '改动立即生效，从下一轮对话开始。',
                  style: AppFonts.body(size: 12, color: s.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(
    AppSurface s,
    int index,
    int value,
    ValueChanged<int> onChanged,
  ) {
    final (String title, String what, String _) = _items[index];

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: AppFonts.body(
                      size: 13.5,
                      weight: FontWeight.w600,
                      color: s.text,
                      height: 1.3),
                ),
              ),
              Text(
                _names[value.clamp(0, 2)],
                style: AppFonts.body(
                    size: 13,
                    weight: FontWeight.w600,
                    color: value == 1 ? s.muted : AppColors.accent),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            what,
            style: AppFonts.body(size: 11.5, color: s.muted, height: 1.45),
          ),
          Slider(
            value: value.toDouble().clamp(0, 2),
            min: 0,
            max: 2,
            divisions: 2,
            label: _names[value.clamp(0, 2)],
            onChanged: (double v) => onChanged(v.round()),
          ),
        ],
      ),
    );
  }
}
