import 'package:flutter/material.dart';

import '../core/python.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';

/// Python 控制台。
///
/// ## 为什么需要它
///
/// Python 本来是给 agent 用的工具，用户不该直接操作。**但调试需要它。**
///
/// 如果 agent 调用失败，你没法判断是：
/// · 解释器根本没起来（构建期/运行期问题）
/// · 还是 agent 没把工具调对（提示词问题）
///
/// 有个控制台就一目了然：这里能跑通 → 问题在 agent 那边；
/// 这里也跑不通 → 问题在 Python 本身，错误信息直接给你看。
///
/// 顺带它也是个趁手的计算器/试验台，不用绕一圈去问 agent。
class PythonConsolePage extends StatefulWidget {
  const PythonConsolePage({super.key});

  @override
  State<PythonConsolePage> createState() => _PythonConsolePageState();
}

class _PythonConsolePageState extends State<PythonConsolePage> {
  final TextEditingController _code = TextEditingController(
    text: 'import sys\nprint(sys.version)',
  );

  PyResult? _result;
  bool _running = false;
  bool _resetNext = false;

  @override
  void initState() {
    super.initState();
    // 进页面时探测一次 —— 让用户马上知道解释器到底起没起来
    PythonService.instance.refresh().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final String code = _code.text;
    if (code.trim().isEmpty) return;

    setState(() {
      _running = true;
      _result = null;
    });

    final PyResult r = await PythonService.instance.run(
      code,
      reset: _resetNext,
    );

    if (!mounted) return;
    setState(() {
      _running = false;
      _result = r;
      _resetNext = false; // 用完就恢复，避免下次误清
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);
    final PythonService py = PythonService.instance;

    return Scaffold(
      backgroundColor: s.isDark ? AppColors.darkBg : AppColors.lightBg,
      body: Column(
        children: <Widget>[
          _header(s),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: <Widget>[
                _statusCard(s, py),
                const SizedBox(height: 14),
                _codeField(s),
                const SizedBox(height: 10),
                _actions(s),
                if (_result != null) ...<Widget>[
                  const SizedBox(height: 16),
                  _outputCard(s, _result!),
                ],
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
      padding: EdgeInsets.fromLTRB(8, top + 6, 14, 10),
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
              'Python 控制台',
              style: AppFonts.body(
                size: 17,
                weight: FontWeight.w700,
                color: s.text,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 解释器状态。**这是这个页面最重要的信息** ——
  /// 它直接回答"Python 到底能不能用"。
  Widget _statusCard(AppSurface s, PythonService py) {
    final bool ok = py.available;

    return SurfaceCard(
      color: (ok ? AppColors.success : AppColors.danger)
          .withValues(alpha: 0.09),
      borderColor: (ok ? AppColors.success : AppColors.danger)
          .withValues(alpha: 0.28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            size: 18,
            color: ok ? AppColors.success : AppColors.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  ok ? '解释器可用' : '解释器不可用',
                  style: AppFonts.body(
                    size: 13.5,
                    weight: FontWeight.w700,
                    color: s.text,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  ok
                      ? (py.version ?? '(已就绪)')
                      : (py.lastError ??
                          '还没探测到。改一下代码点运行，结果会显示在下面。'),
                  style: AppFonts.code(size: 11, color: s.muted),
                ),
                if (ok) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    py.packages == null
                        ? '内嵌 CPython · 无需任何配置'
                        : '已装 ${py.packages!.length} 个第三方包',
                    style:
                        AppFonts.body(size: 11.5, color: s.muted, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeField(AppSurface s) {
    return Container(
      decoration: ShapeDecoration(
        color: s.codeBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.code),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: TextField(
        controller: _code,
        minLines: 5,
        maxLines: 14,
        keyboardType: TextInputType.multiline,
        // 代码一律等宽，否则缩进看不出层级
        style: AppFonts.code(size: 12.5, color: s.text, height: 1.55),
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          hintText: 'print("hello")',
          hintStyle: AppFonts.code(size: 12.5, color: s.muted),
        ),
      ),
    );
  }

  Widget _actions(AppSurface s) {
    return Row(
      children: <Widget>[
        GlassButton(
          label: _running ? '运行中…' : '运行',
          icon: _running ? null : Icons.play_arrow_rounded,
          accent: true,
          onTap: _running ? null : _run,
        ),
        const SizedBox(width: 9),
        GlassButton(
          label: '清空变量',
          icon: Icons.restart_alt_rounded,
          fontSize: 13,
          onTap: () {
            // 只是**标记**下次运行前清空，不立即执行 ——
            // 用户按下按钮时往往接着就要写新代码，立即清空没有意义
            setState(() => _resetNext = true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('下次运行前会清空之前定义的变量'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
        const Spacer(),
        if (_resetNext)
          Text(
            '待清空',
            style: AppFonts.body(size: 11.5, color: AppColors.warning),
          ),
      ],
    );
  }

  Widget _outputCard(AppSurface s, PyResult r) {
    final Color tint = r.ok ? AppColors.success : AppColors.danger;
    final String text = r.ok
        ? (r.output.trim().isEmpty ? '（没有输出）' : r.output.trim())
        : '${r.errorType ?? 'Exception'}\n\n${r.error ?? ''}'
            '${r.output.trim().isEmpty ? '' : '\n\n--- 报错前已产生的输出 ---\n${r.output.trim()}'}';

    return SurfaceCard(
      color: tint.withValues(alpha: 0.07),
      borderColor: tint.withValues(alpha: 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                r.ok ? Icons.terminal_rounded : Icons.bug_report_rounded,
                size: 15,
                color: tint,
              ),
              const SizedBox(width: 7),
              Text(
                r.ok ? '输出' : '出错了',
                style: AppFonts.body(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: tint,
                  height: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            text,
            // 输出用 SelectableText 而不是 Text：报错信息经常要复制出去搜，
            // 而 markdown 那边的 RichText 是选不中的（踩过这个坑）。
            style: AppFonts.code(size: 11.5, color: s.text, height: 1.55),
          ),
        ],
      ),
    );
  }
}
