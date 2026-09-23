import '../core/models.dart';
import '../core/termux.dart';
import 'risk.dart';
import 'tool.dart';

/// Termux 工具：在手机上执行真正的 Linux 命令。
///
/// 和 `run_shell`（Shizuku）的区别：
/// · `run_shell` 拿到的是 Android 的 shell（adb 权限），命令是 `pm` / `settings` 这类
/// · `termux` 拿到的是**一套完整的 Linux 用户空间** —— 有 python、node、git、
///   clang、ffmpeg，而且 `pkg install` 能装两千多个包
///
/// **真正的分水岭在于"能验证"**：agent 可以写一段脚本、真的跑起来、看懂报错、
/// 改完再跑。没有它的时候，agent 只能把代码写给你，你自己去跑。
class TermuxTool extends AgentTool {
  const TermuxTool();

  @override
  String get name => 'termux';

  @override
  String get title => 'Termux';

  @override
  String get description =>
      '在 Termux 的 Linux 环境里执行命令。**优先用它而不是 run_shell** —— '
      '它有完整的软件生态（python / node / git / clang / ffmpeg 等，'
      '可用 pkg install 装包），而 run_shell 只有 Android 自带的那几条命令。\n'
      '什么时候用：写代码并**实际运行验证**、用 python 做数据/图像处理、'
      '跑 git、编译小程序、用 ffmpeg 处理媒体。\n'
      '注意：\n'
      '· 命令用 `bash -lc` 执行，所以 `pkg` `python` 这些都在 PATH 里\n'
      '· **交互式命令会挂住**（apt 问 y/n、ssh 要密码）—— 用 `-y`、'
      '`--non-interactive`、`GIT_TERMINAL_PROMPT=0` 这类方式绕开\n'
      '· 长时间任务（编译）用 background=true 并把输出重定向到文件，'
      '之后用 file_op 读那个文件，不要干等';

  @override
  Map<String, dynamic> get parameters => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'command': <String, dynamic>{
            'type': 'string',
            'description': '要执行的命令。可以是一长串（用 && 串联），'
                '也可以先写个脚本再 bash 它。',
          },
          'workdir': <String, dynamic>{
            'type': 'string',
            'description': '工作目录。注意 Termux 的 home 是 '
                '/data/data/com.termux/files/home，手机存储是 /sdcard',
          },
          'background': <String, dynamic>{
            'type': 'boolean',
            'description': 'true 时立即返回、不等结果（长任务用）。'
                '此时拿不到输出，请自行重定向到文件。',
          },
          'timeout_sec': <String, dynamic>{
            'type': 'integer',
            'description': '前台模式等待秒数，默认 60，上限 300',
          },
        },
        'required': <String>['command'],
      };

  @override
  RiskAssessment riskFor(Map<String, dynamic> args) {
    return TermuxRisk.classify(args.str('command'));
  }

  @override
  String summarize(Map<String, dynamic> args) {
    final String c = args.str('command').trim().replaceAll(RegExp(r'\s+'), ' ');
    final String short = c.length > 120 ? '${c.substring(0, 120)}…' : c;
    return args.boolVal('background', fallback: false)
        ? '[后台] $short'
        : short;
  }

  @override
  Future<String> run(ToolContext ctx, Map<String, dynamic> args) async {
    final TermuxService t = TermuxService.instance;

    if (t.status == TermuxStatus.notInstalled) {
      return 'Termux 未安装。\n\n'
          '这个工具需要用户先装 Termux（注意：Play 商店那版已废弃，'
          '要从 F-Droid 装）。\n'
          '装好后还需要在 Termux 里执行一次：\n'
          '  echo \'allow-external-apps=true\' >> ~/.termux/termux.properties\n'
          '  termux-reload-settings';
    }

    final String command = args.str('command');
    if (command.trim().isEmpty) return '错误：缺少 command';

    final bool background = args.boolVal('background', fallback: false);
    final int timeoutSec =
        args.intVal('timeout_sec', fallback: 60).clamp(5, 300);

    final TermuxResult r = await t.run(
      command,
      workdir: args.str('workdir').trim().isEmpty
          ? null
          : args.str('workdir').trim(),
      background: background,
      timeout: Duration(seconds: timeoutSec),
    );

    if (!r.ok) {
      return 'Termux 执行失败：${r.error ?? '未知原因'}\n'
          '${r.combined.trim().isEmpty ? '' : '\n输出：\n${clampOutput(r.combined, max: 3000)}'}';
    }

    if (r.background) {
      return '已在后台启动。\n'
          '输出不会回传 —— 如果之后要看进度，请把命令改成重定向到文件的形式，'
          '例如：`$command > /sdcard/dsh/job.log 2>&1`，'
          '然后用 `file_op` 的 read 去读它。';
    }

    final String out = clampOutput(r.combined, max: 8000);
    // 退出码非 0 时明确标出来：模型需要知道"它失败了"，
    // 否则会把报错当成正常输出继续往下推理
    final String head = r.exitCode == 0
        ? ''
        : '（退出码 ${r.exitCode} —— 命令没有成功执行）\n';
    return '$head$out';
  }
}

/// Termux 命令的风险分级。
///
/// 和 Android shell 的分级**共用同一套思路**（fail-safe：认不出来就要确认），
/// 但白名单必须单独写 —— 两边的命令集合几乎不重叠。
///
/// 这条尤其重要：**Termux 能装包、能跑任意脚本**，
/// 所以 `curl … | bash` 这类必须按危险处理，不能让 agent 自动执行
/// 一段从网上拉下来的代码。
class TermuxRisk {
  const TermuxRisk._();

  /// 明确的只读命令 —— 只有这些能自动执行
  static final List<RegExp> _safe = <RegExp>[
    RegExp(r'^\s*(ls|pwd|whoami|id|uname|date|which|type|env)\b'),
    RegExp(r'^\s*(cat|head|tail|wc|file|stat|du|df)\b'),
    RegExp(r'^\s*(grep|rg|find|fd|sort|uniq|cut|tr)\b'),
    RegExp(r'^\s*git\s+(status|log|diff|show|branch|remote|describe)\b'),
    RegExp(r'^\s*(python3?|node)\s+(-V|--version|-c\s+[\x27"]print)'),
    RegExp(r'^\s*(pkg|apt)\s+(list|show|search)\b'),
    RegExp(r'^\s*(pip|npm|go|cargo)\s+(list|show|--version|-V)\b'),
    RegExp(r'^\s*echo\b'),
    RegExp(r'^\s*termux-\w+\s*$'),
  ];

  /// 破坏性、不可撤销
  static final List<RegExp> _dangerous = <RegExp>[
    // 从网上直接拉代码执行 —— Termux 场景下这是最危险的一类
    RegExp(r'\b(curl|wget)\b[^|;]*\|\s*(sudo\s+)?(ba|z|d)?sh\b'),
    RegExp(r'\b(base64|eval|source)\b.*\|\s*(ba|z|d)?sh\b'),
    RegExp(r'\brm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)+/'),
    RegExp(r'\brm\s+-[a-zA-Z]*[rf][a-zA-Z]*\s+(/sdcard|/storage|/data|\$HOME|~)\s*$'),
    RegExp(r'\bmkfs|\bdd\s+if=|\bshred\b'),
    RegExp(r'\bchmod\s+(-R\s+)?777\s+/'),
    RegExp(r'\bsudo\b'),
    RegExp(r'>\s*/dev/block/'),
    RegExp(r'\b(reboot|poweroff|halt)\b'),
    RegExp(r':\(\)\s*\{.*\};\s*:'), // fork bomb
  ];

  /// 会改变状态但可逆 —— 需要确认
  static final List<RegExp> _caution = <RegExp>[
    RegExp(r'\b(pkg|apt|apt-get)\s+(install|remove|upgrade|update|purge)\b'),
    RegExp(r'\b(pip|npm|yarn|pnpm)\s+(install|add|remove|uninstall)\b'),
    RegExp(r'\b(go|cargo)\s+(get|install|add|build|run)\b'),
    RegExp(r'\bgit\s+(clone|pull|push|fetch|checkout|reset|clean|commit)\b'),
    RegExp(r'\b(rm|mv|cp|mkdir|rmdir|touch|ln)\b'),
    RegExp(r'\b(make|cmake|ninja|gcc|clang|javac)\b'),
    RegExp(r'\bffmpeg\b|\bconvert\b|\bmagick\b'),
    RegExp(r'>\s*\S'), // 任何重定向写入
    RegExp(r'\|\s*(tee|dd)\b'),
  ];

  static RiskAssessment classify(String rawCommand) {
    final String cmd = rawCommand.trim();
    if (cmd.isEmpty) {
      return const RiskAssessment(RiskLevel.caution, <String>['空命令']);
    }

    // 引号感知切分 —— **直接复用 Android 那边的实现**，不另写一份。
    // 两边各写一份迟早会不一致，而这是安全相关的逻辑，
    // 不一致就意味着某一边能绕过。
    final List<String> segments = RiskClassifier.splitSegments(cmd);

    RiskLevel worst = RiskLevel.safe;
    final List<String> reasons = <String>[];

    for (final String seg in segments) {
      final String s = seg.trim();
      if (s.isEmpty) continue;

      for (final RegExp re in _dangerous) {
        if (re.hasMatch(s)) {
          return RiskAssessment(
            RiskLevel.dangerous,
            <String>['危险命令：${_short(s)}'],
          );
        }
      }

      if (worst == RiskLevel.safe) {
        bool cautionHit = false;
        for (final RegExp re in _caution) {
          if (re.hasMatch(s)) {
            cautionHit = true;
            break;
          }
        }
        if (cautionHit) {
          worst = RiskLevel.caution;
          reasons.add('会改变状态：${_short(s)}');
        }
      }

      // 白名单只对**单段**生效：命令被拆成多段时，
      // 只要有一段不匹配白名单，就整体不信任
      if (worst == RiskLevel.safe) {
        bool safeHit = false;
        for (final RegExp re in _safe) {
          if (re.hasMatch(s)) {
            safeHit = true;
            break;
          }
        }
        if (!safeHit) {
          worst = RiskLevel.caution;
          reasons.add('无法确认只读：${_short(s)}');
        }
      }
    }

    if (worst == RiskLevel.safe) return RiskAssessment.safe;
    return RiskAssessment(worst, reasons.isEmpty ? <String>['需要确认'] : reasons);
  }

  static String _short(String s) =>
      s.length > 60 ? '${s.substring(0, 60)}…' : s;
}
