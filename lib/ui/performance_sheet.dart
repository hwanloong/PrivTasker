import 'package:flutter/material.dart';

import '../core/metrics.dart';
import '../core/store.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';

/// 性能面板：缓存命中 / token 用量 / 上下文占用。
///
/// 有一条必须守住的底线：**实测值和估算值要分开显示**。
/// token 只有 API 真的返回了 `usage` 才是准的，否则只能用本地经验规则估。
/// 把估算值伪装成实测值，用户拿去对账就会发现对不上，
/// 那时候他不会再信任面板上的任何数字。
Future<void> showPerformanceSheet(
  BuildContext context, {
  required Settings settings,
  int contextTokens = 0,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext ctx) => _PerformanceSheet(
      settings: settings,
      contextTokens: contextTokens,
    ),
  );
}

class _PerformanceSheet extends StatefulWidget {
  const _PerformanceSheet({required this.settings, required this.contextTokens});

  final Settings settings;
  final int contextTokens;

  @override
  State<_PerformanceSheet> createState() => _PerformanceSheetState();
}

class _PerformanceSheetState extends State<_PerformanceSheet> {
  @override
  void initState() {
    super.initState();
    AppMetrics.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    AppMetrics.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);
    final AppMetrics m = AppMetrics.instance;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: s.isDark ? AppColors.darkBg : AppColors.lightBg,
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
                Text(
                  '性能',
                  style: AppFonts.body(
                    size: 17,
                    weight: FontWeight.w700,
                    color: s.text,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: <Widget>[
                // ---------------- 缓存 ----------------
                _section(s, '搜索缓存'),
                _metricCard(
                  s,
                  icon: Icons.bolt_rounded,
                  title: '命中率',
                  value: m.cacheHitRate == null
                      ? '—'
                      : '${(m.cacheHitRate! * 100).toStringAsFixed(0)}%',
                  desc: m.searchCacheTotal == 0
                      ? '还没有搜索过。相同关键词在 10 分钟内会直接命中缓存。'
                      : '命中 ${m.searchCacheHits} 次 / 未命中 ${m.searchCacheMisses} 次，'
                          '共 ${m.searchCacheTotal} 次查询。',
                  accent: m.cacheHitRate != null && m.cacheHitRate! > 0.3,
                ),

                // ---------------- token ----------------
                _section(s, 'Token 用量（本次运行）'),
                _metricCard(
                  s,
                  icon: Icons.data_usage_rounded,
                  title: '总计',
                  value: AppMetrics.humanCount(m.totalTokens),
                  desc: '调用 ${m.callCount} 次 · '
                      '输入 ${AppMetrics.humanCount(m.promptTokens)} · '
                      '输出 ${AppMetrics.humanCount(m.completionTokens)}'
                      '${m.reasoningTokens > 0 ? ' · 思维链 ${AppMetrics.humanCount(m.reasoningTokens)}' : ''}',
                ),

                // 实测 / 估算的区分，这是整个面板最需要说清楚的一点
                if (m.callCount > 0)
                  SurfaceCard(
                    margin: const EdgeInsets.only(bottom: 9),
                    color: m.hasMeasuredUsage
                        ? AppColors.success.withValues(alpha: 0.08)
                        : AppColors.warning.withValues(alpha: 0.10),
                    borderColor: (m.hasMeasuredUsage
                            ? AppColors.success
                            : AppColors.warning)
                        .withValues(alpha: 0.30),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          m.hasMeasuredUsage
                              ? Icons.verified_rounded
                              : Icons.info_outline_rounded,
                          size: 16,
                          color: m.hasMeasuredUsage
                              ? AppColors.success
                              : AppColors.warning,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            m.hasMeasuredUsage
                                ? '其中 ${m.measuredCalls} 次是服务端实测值'
                                    '${m.estimatedCalls > 0 ? '，${m.estimatedCalls} 次为本地估算' : ''}。'
                                : '服务端没有返回 usage，以下全部是**本地估算**：'
                                    '按「中文约 1 token/字、其余约 1 token/4 字符」估算，'
                                    '只能用于感知量级，不能当作计费依据。',
                            style: AppFonts.body(
                              size: 12.3,
                              color: s.text,
                              height: 1.55,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ---------------- 上下文 ----------------
                _section(s, '上下文占用'),
                _contextCard(s, m),

                const SizedBox(height: 14),
                Center(
                  child: GlassButton(
                    label: '重置统计',
                    icon: Icons.restart_alt_rounded,
                    fontSize: 13,
                    onTap: () => AppMetrics.instance.reset(),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '统计只保存在本次运行内，应用退出后清零',
                    style: AppFonts.body(size: 11.5, color: s.muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contextCard(AppSurface s, AppMetrics m) {
    // 优先用实时算出来的当前会话用量；没有就退回记录的最近一次
    final int tokens =
        widget.contextTokens > 0 ? widget.contextTokens : m.lastContextTokens;
    final int limit = _contextLimit(widget.settings.model);
    final double ratio = limit <= 0 ? 0 : (tokens / limit).clamp(0.0, 1.0);

    final Color barColor = ratio > 0.8
        ? AppColors.danger
        : ratio > 0.5
            ? AppColors.warning
            : AppColors.accent;

    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.memory_rounded, size: 16, color: s.muted),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  widget.settings.model,
                  style: AppFonts.code(size: 12.5, color: s.text),
                ),
              ),
              Text(
                limit <= 0
                    ? '—'
                    : '${AppMetrics.humanCount(tokens)} / ${AppMetrics.humanCount(limit)}',
                style: AppFonts.code(size: 12, color: s.muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: limit <= 0 ? 0 : ratio,
              minHeight: 6,
              backgroundColor: s.border,
              color: barColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tokens == 0
                ? '还没有发送过消息。'
                : '当前会话约占 ${(ratio * 100).toStringAsFixed(1)}%。'
                    '${ratio > 0.8 ? '接近上限，建议开新会话。' : ''}'
                    '（按文本长度估算）',
            style: AppFonts.body(size: 12, color: s.muted, height: 1.5),
          ),
        ],
      ),
    );
  }

  /// 各模型的上下文窗口。拿不准就给一个保守值 ——
  /// 高估会让用户以为还有余量，实际早就该开新会话了。
  static int _contextLimit(String model) {
    final String m = model.toLowerCase();
    if (m.contains('flash')) return 1000000; // V4.1 Flash 标称 1M
    if (m.contains('pro')) return 1000000;
    return 128000;
  }

  Widget _section(AppSurface s, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
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

  Widget _metricCard(
    AppSurface s, {
    required IconData icon,
    required String title,
    required String value,
    required String desc,
    bool accent = false,
  }) {
    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon,
                  size: 16,
                  color: accent ? AppColors.success : s.muted),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: AppFonts.body(
                      size: 13.5, color: s.muted, height: 1.3),
                ),
              ),
              Text(
                value,
                style: AppFonts.body(
                  size: 22,
                  weight: FontWeight.w700,
                  color: accent ? AppColors.success : s.text,
                  height: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            desc,
            style: AppFonts.body(size: 12, color: s.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}
