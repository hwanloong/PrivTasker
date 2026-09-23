import '../core/models.dart';
import '../core/python.dart';
import 'tool.dart';

/// 内嵌 Python 工具。
///
/// **这是整个应用能力最强的一个工具**：它让 agent 能写代码并**立刻运行验证**。
///
/// 没有它的时候，agent 只能把代码写给你，你自己去跑、自己看报错、自己回来告诉它；
/// 有了它，agent 能自己发现代码跑不通、自己改、再跑 —— 从"给建议"变成"交付"。
///
/// 和 `termux` 的区别：
/// · `termux` 是**完整的 Linux 环境**（有 git、ffmpeg、clang、包管理），
///   但需要用户自己装 Termux 并配置
/// · `python` 是**应用自带的解释器**，用户零配置，但只有 Python 和已装的库
///
/// 两者不冲突：简单计算/数据处理用 `python`（快、无需配置），
/// 需要外部工具链时用 `termux`。
class PythonTool extends AgentTool {
  const PythonTool();

  @override
  String get name => 'python';

  @override
  String get title => 'Python';

  @override
  String get description =>
      '执行 Python 代码并拿到输出。**这是应用自带的解释器，不需要任何配置。**\n'
      '什么时候用：\n'
      '· 需要精确计算（大数、浮点、循环、统计）—— 别自己心算，写代码跑\n'
      '· 文本处理、正则、编码转换、JSON/CSV 整理\n'
      '· 写一段脚本验证某个想法对不对\n'
      '· 用已装的第三方库处理数据（openpyxl 操作 Excel 等）\n'
      '注意：\n'
      '· **会话是连续的**：上一次定义的变量这一次还在，像 REPL 一样。'
      '要清空就用 reset=true\n'
      '· 返回的是 print 出来的内容。最后一行是表达式的话会自动显示它的值\n'
      '· 报错会带上完整的 traceback —— **仔细看它，它能告诉你哪一行错了**\n'
      '· 这是 CPython，但只装了有限的第三方库；缺库时告诉用户需要重新构建应用，'
      '不要假装装上了';

  @override
  Map<String, dynamic> get parameters => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'code': <String, dynamic>{
            'type': 'string',
            'description': '要执行的 Python 代码。可以多行。',
          },
          'reset': <String, dynamic>{
            'type': 'boolean',
            'description': 'true 时先清空之前定义的变量，从头开始。默认 false。',
          },
        },
        'required': <String>['code'],
      };

  @override
  RiskAssessment riskFor(Map<String, dynamic> args) {
    return PythonRisk.classify(args.str('code'));
  }

  @override
  String summarize(Map<String, dynamic> args) {
    final String c = args.str('code').trim().replaceAll(RegExp(r'\s+'), ' ');
    return c.length > 140 ? '${c.substring(0, 140)}…' : c;
  }

  @override
  Future<String> run(ToolContext ctx, Map<String, dynamic> args) async {
    final PythonService py = PythonService.instance;

    // 不可用时**也要给出可诊断的信息**，而不是一句"用不了"。
    // 这条路径以前根本走不到（工具会被藏起来），所以没人在意它的措辞；
    // 现在工具无条件注册，这里就是用户唯一能看到原因的地方。
    if (!py.available && py.lastError != null) {
      return '内嵌 Python 不可用：${py.lastError}\n\n'
          '排查方向（这是应用自带解释器，**不需要用户装任何东西**，'
          '所以问题一定在构建或运行期）：\n'
          '· 打开「设置 → Python 控制台」看具体报错 —— 那里有完整信息\n'
          '· 如果报 UnsatisfiedLinkError / SoLoader 之类：原生库没加载成功，'
          '通常是 ABI 不匹配（本应用只出 arm64-v8a 和 x86_64）\n'
          '· 如果报 ModuleNotFoundError: dsh_runner：Python 源码没打进包\n'
          '· 把上面这段原文告诉用户，让他反馈';
    }

    final String code = args.str('code');
    if (code.trim().isEmpty) return '错误：缺少 code';

    final PyResult r = await py.run(
      code,
      reset: args.boolVal('reset', fallback: false),
    );

    if (r.ok) {
      final String out = r.output.trim();
      if (out.isEmpty) {
        // 空输出很常见（比如只做了赋值），但直接说"无输出"模型会以为出错了
        return '（执行成功，没有输出。如果想让结果可见，用 print(...) 打印它。）';
      }
      return clampOutput(out, max: 8000);
    }

    // 失败时把 traceback 原样给出去 —— 模型要靠它定位问题。
    // 前面加一行醒目的标记，避免它把报错当成正常输出继续往下推理。
    final StringBuffer sb = StringBuffer();
    sb.writeln('执行失败（${r.errorType ?? 'Exception'}）');
    if (r.output.trim().isNotEmpty) {
      sb.writeln('在报错前已产生的输出：');
      sb.writeln(r.output.trim());
      sb.writeln();
    }
    sb.write(clampOutput(r.error ?? '（没有错误详情）', max: 4000));
    return sb.toString();
  }
}

/// Python 代码的风险分级。
///
/// **这个工具比 shell 危险等级更高** —— 它不经过 Android 的权限模型，
/// 直接在应用进程里跑，能读写应用能碰的一切（包括笔记、会话、API Key 文件）。
///
/// 所以策略是**明显更保守**：
/// · 只读、纯计算 → 自动执行
/// · 任何文件写入 / 网络 / 子进程 → 需确认
/// · 删除、改系统、动态执行远程代码 → 危险
class PythonRisk {
  const PythonRisk._();

  /// 明确只读或纯计算
  static final List<RegExp> _safe = <RegExp>[
    // 纯数学/字符串，完全无副作用
    RegExp(r'^\s*[\d\s+\-*/%().,eE_*]+$'),
  ];

  /// 明确危险
  static final List<RegExp> _dangerous = <RegExp>[
    // 删文件、改权限
    RegExp(r'\b(os\.remove|os\.unlink|os\.rmdir|shutil\.rmtree)\b'),
    RegExp(r'\b(os\.chmod|os\.chown)\b'),
    // 动态执行外部代码 —— 和 shell 的 `curl | bash` 是同一类风险
    RegExp(r'\b(exec|eval)\s*\('),
    RegExp(r'\b__import__\s*\('),
    RegExp(r'\b(compile|globals|locals)\s*\('),
    RegExp(r'\bimportlib\b.*\bimport_module\b'),
    // 起子进程 / 系统调用
    RegExp(r'\b(subprocess|os\.system|os\.popen|os\.exec|pty\.spawn)\b'),
    RegExp(r'\b(ctypes|cffi)\b'),
    // 直接读写系统路径
    RegExp(r'open\s*\(\s*[\x27"]/(system|data|proc|sys|dev)'),
    // 起网络服务 / 反向 shell
    RegExp(r'\b(socket\.socket|bind\s*\(|listen\s*\()'),
  ];

  /// 会改变状态、需要确认
  static final List<RegExp> _caution = <RegExp>[
    // 文件写入
    RegExp(r'\bopen\s*\([^)]*[\x27"][wax]'),
    RegExp(r'\b(os\.mkdir|os\.makedirs|os\.rename|os\.replace|shutil\.)\b'),
    RegExp(r'\b(pathlib\.Path)[^\n]*\.(write_text|write_bytes|unlink|mkdir)'),
    // 网络请求
    RegExp(r'\b(requests|urllib|httpx|urlopen|urlretrieve)\b'),
    // 装包
    RegExp(r'\b(pip|subprocess\.check_call.*pip)\b'),
    // 大内存操作，可能把应用拖死
    RegExp(r'\b(numpy\.zeros|numpy\.ones|numpy\.empty)\s*\(\s*\d{7,}'),
  ];

  static RiskAssessment classify(String code) {
    final String c = code.trim();
    if (c.isEmpty) {
      return const RiskAssessment(RiskLevel.caution, <String>['空代码']);
    }

    // 危险模式先扫 —— 一旦命中直接判危险，不再往下看
    for (final RegExp re in _dangerous) {
      if (re.hasMatch(c)) {
        return RiskAssessment(
          RiskLevel.dangerous,
          <String>['危险操作：${_short(c)}'],
        );
      }
    }

    for (final RegExp re in _caution) {
      if (re.hasMatch(c)) {
        return RiskAssessment(
          RiskLevel.caution,
          <String>['会改变状态或访问网络：${_short(c)}'],
        );
      }
    }

    // 只读判定要比 shell 严得多：Python 里"没有明显副作用"不等于安全，
    // 所以只有**极窄**的纯表达式才放行，其余一律要确认。
    // 这不是保守过头 —— 这个工具能在应用进程里为所欲为，
    // 宁可多问一次，也不能让一段没看清的代码自动跑。
    final bool looksPure = !c.contains('import ') &&
        !c.contains('open(') &&
        !c.contains('=') && // 赋值也可能有副作用（属性 setter）
        RegExp(r'^[\s\d+\-*/%().,eE_\[\]:\x27"]+$').hasMatch(c);

    if (looksPure) return RiskAssessment.safe;

    return RiskAssessment(
      RiskLevel.caution,
      <String>['含代码执行：${_short(c)}'],
    );
  }

  static String _short(String s) =>
      s.length > 60 ? '${s.substring(0, 60)}…' : s;
}
