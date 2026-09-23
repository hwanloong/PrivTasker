import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';

/// 工具调用的一行式显示。
///
/// 设计取舍：**默认只占一行**。
///
/// 之前的卡片会展开显示命令原文 + 完整输出，一次对话里几个工具调用就把
/// 屏幕占满了，正文（模型真正说的话）反而被挤到看不见。
/// 而现在这些细节多数时候并不需要看 —— 用户关心的是"它干了什么"，
/// 不是"它输入的 JSON 长什么样"。
///
/// 所以：**一行摘要 + 一个风险色点**，想看细节点一下展开。
class ToolLine extends StatefulWidget {
  const ToolLine({super.key, required this.invocation});

  final ToolInvocation invocation;

  @override
  State<ToolLine> createState() => _ToolLineState();
}

class _ToolLineState extends State<ToolLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final ToolInvocation inv = widget.invocation;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            // 圆点**和正文的左边对齐**，文字跟在它后面。
            //
            // 这里返璞归真了：之前为了让"文字"和正文对齐，把圆点悬挂到
            // 左边距外面 —— 结果文字对齐了，圆点却飘在栏外、和任何东西都不成线，
            // 看着更别扭。
            //
            // 正确的做法就是普通的项目符号布局：圆点占住文字栏的左边界，
            // 后面跟一个固定间距，再是文字。圆点对齐了，一行才有"起点"。
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                _dot(inv),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: '${_shortName(inv.name)}：',
                          style: AppFonts.body(
                            size: 13,
                            weight: FontWeight.w700,
                            color: AppColors.accent,
                            height: 1.35,
                          ),
                        ),
                        TextSpan(
                          text: _summary(inv),
                          style: AppFonts.body(
                            size: 13,
                            color: AppSurface.of(context).muted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // 展开指示：箭头而不是文字，省空间
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 17,
                    color: AppSurface.of(context).muted,
                  ),
                ),
              ],
            ),
          ),
          if (_open) _detail(context, inv),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 风险色点

  /// 一个小圆点代表安全性。这是这一行里**唯一表达状态的东西**，
  /// 所以必须让四种状态一眼可分：
  ///   绿 = 只读、已自动执行
  ///   琥珀 = 需确认（或已拒绝）
  ///   红 = 危险操作
  ///   转动 = 正在执行
  /// 失败时用红色叉覆盖，不再保留原本的安全色 ——
  /// 出错了还显示绿色会误导。
  Widget _dot(ToolInvocation inv) {
    if (inv.status == InvocationStatus.running) {
      return SizedBox(
        width: 11,
        height: 11,
        child: CircularProgressIndicator(
          strokeWidth: 1.8,
          color: AppColors.accent,
        ),
      );
    }

    Color color;
    if (inv.status == InvocationStatus.failed) {
      color = AppColors.danger;
    } else if (inv.status == InvocationStatus.rejected) {
      color = AppColors.neutral;
    } else {
      color = switch (inv.risk.level) {
        RiskLevel.safe => AppColors.success,
        RiskLevel.caution => AppColors.warning,
        RiskLevel.dangerous => AppColors.danger,
      };
    }

    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  // ------------------------------------------------------------ 摘要文本

  /// 工具名缩短：`run_shell` → `shell`，`read_image` → `image`
  static String _shortName(String name) {
    return switch (name) {
      'run_shell' => 'shell',
      'read_image' => 'image',
      'screen_capture' => 'capture',
      'system_settings' => 'settings',
      'app_manage' => 'apps',
      'file_op' => 'file',
      'browser' => 'browser',
      'web' => 'web',
      'notes' => 'note',
      'tasks' => 'task',
      _ => name,
    };
  }

  /// 从参数里挑出最有信息量的那一项做摘要。
  ///
  /// 按优先级找，而不是把整个 JSON 打出来 ——
  /// 一行里能显示的字很少，`{"action":"search","query":"x","limit":5}` 这种
  /// 原文对用户毫无意义。
  static String _summary(ToolInvocation inv) {
    final Map<String, dynamic> a = inv.args;

    String? pick(List<String> keys) {
      for (final String k in keys) {
        final dynamic v = a[k];
        if (v == null) continue;
        final String s = v.toString().trim();
        if (s.isNotEmpty && s != 'null') return s;
      }
      return null;
    }

    final String? action = pick(<String>['action']);
    final String? main = pick(<String>[
      'command',
      'query',
      'url',
      'path',
      'src',
      'title',
      'package',
      'keyword',
      'id',
    ]);

    final StringBuffer sb = StringBuffer();
    if (action != null) sb.write('$action ');
    if (main != null) {
      sb.write(main);
    } else if (a.isNotEmpty) {
      // 兜底：所有值拼起来，但截断
      final String joined = a.values
          .map((dynamic v) => v.toString())
          .where((String s) => s.trim().isNotEmpty)
          .join(' ');
      sb.write(joined);
    }

    final String text = sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return '（无参数）';
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }

  // ------------------------------------------------------------ 展开详情

  Widget _detail(BuildContext context, ToolInvocation inv) {
    final AppSurface s = AppSurface.of(context);

    return Padding(
      // 左边距为 0：摘要文字从 x=0 开始，和上面的 AI 正文对齐。
      // 圆点由外层悬挂到左边距里，不占这个位置。
      padding: const EdgeInsets.only(top: 7, bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 风险原因（只有需要确认/危险时才有内容）
          if (inv.risk.reasons.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                inv.risk.reasons.join('；'),
                style: AppFonts.body(
                  size: 11.5,
                  color: inv.risk.level == RiskLevel.dangerous
                      ? AppColors.danger
                      : s.muted,
                  height: 1.5,
                ),
              ),
            ),

          // 完整参数
          _box(
            s,
            '参数',
            const JsonEncoder.withIndent('  ').convert(inv.args),
          ),

          if (inv.output != null && inv.output!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 7),
            _box(s, '输出', inv.output!),
          ],
        ],
      ),
    );
  }

  Widget _box(AppSurface s, String label, String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: AppFonts.body(size: 10.5, color: s.muted, height: 1.3),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: ShapeDecoration(
            color: s.codeBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.code),
            ),
          ),
          child: Text(
            text.length > 4000 ? '${text.substring(0, 4000)}…' : text,
            style: AppFonts.code(size: 11.5, color: s.text, height: 1.5),
          ),
        ),
      ],
    );
  }
}
