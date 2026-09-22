import '../core/models.dart';

/// shell 命令的风险分级器。
///
/// 核心原则是 **fail-safe（失败即保守）**：
///   · 只有明确落在只读白名单里的命令才判定为 [RiskLevel.safe]；
///   · 认不出来的一律判 [RiskLevel.caution]，绝不静默放行；
///   · 命中破坏性特征判 [RiskLevel.dangerous]。
///
/// 另外两点容易被忽略、但必须处理：
///  1. **引号感知的切分**。`grep -E 'level|status'` 里的 `|` 在引号内，
///     按 `|` 无脑切分会把一条命令拆错，导致误判。
///  2. **多段命令取最高风险**。`ls; rm -rf /` 不能因为第一段安全就放行。
class RiskClassifier {
  const RiskClassifier._();

  /// 只读白名单：这些命令（及其常见只读参数组合）不改动任何状态。
  static final List<RegExp> _safePrefixes = <RegExp>[
    RegExp(r'^ls(\s|$)'),
    RegExp(r'^cat(\s|$)'),
    RegExp(r'^head(\s|$)'),
    RegExp(r'^tail(\s|$)'),
    RegExp(r'^wc(\s|$)'),
    RegExp(r'^stat(\s|$)'),
    RegExp(r'^file(\s|$)'),
    RegExp(r'^md5sum(\s|$)'),
    RegExp(r'^sha1sum(\s|$)'),
    RegExp(r'^sha256sum(\s|$)'),
    RegExp(r'^getprop(\s|$)'),
    RegExp(r'^dumpsys(\s|$)'),
    RegExp(r'^df(\s|$)'),
    RegExp(r'^du(\s|$)'),
    RegExp(r'^free(\s|$)'),
    RegExp(r'^uptime(\s|$)'),
    RegExp(r'^date(\s|$)'),
    RegExp(r'^id(\s|$)'),
    RegExp(r'^whoami(\s|$)'),
    RegExp(r'^uname(\s|$)'),
    RegExp(r'^ps(\s|$)'),
    RegExp(r'^pidof(\s|$)'),
    RegExp(r'^echo(\s|$)'),
    RegExp(r'^grep(\s|$)'),
    RegExp(r'^sort(\s|$)'),
    RegExp(r'^uniq(\s|$)'),
    RegExp(r'^cut(\s|$)'),
    RegExp(r'^tr(\s|$)'),
    RegExp(r'^netstat(\s|$)'),
    RegExp(r'^wm\s+(size|density)(\s|$)'),
    RegExp(r'^pm\s+(list|path)(\s|$)'),
    RegExp(r'^cmd\s+package\s+(list|path)(\s|$)'),
    RegExp(r'^settings\s+(get|list)(\s|$)'),
    RegExp(r'^ip\s+(addr|link|route)(\s|$)'),
    RegExp(r'^logcat\s+-d(\s|$)'),
    RegExp(r'^dumpsys\s'),
    RegExp(r'^which(\s|$)'),
    RegExp(r'^readlink(\s|$)'),
    RegExp(r'^realpath(\s|$)'),
  ];

  /// 破坏性特征 —— 命中即 dangerous
  static final List<(RegExp, String)> _dangerousPatterns =
      <(RegExp, String)>[
    (
      RegExp(r'\brm\b[^|;]*\s-[a-zA-Z]*[rf]'),
      '包含 rm 的递归/强制删除，删除后无法恢复'
    ),
    (RegExp(r'\bpm\s+clear\b'), 'pm clear 会清除目标的全部数据（登录状态、本地文件等），不可撤销'),
    (RegExp(r'\bpm\s+uninstall\b'), 'pm uninstall 会卸载应用，其数据一并丢失'),
    (RegExp(r'\bpm\s+disable(-user)?\b'), 'pm disable 会停用应用，可能导致系统组件异常'),
    (RegExp(r'\bmkfs(\.\w+)?\b'), 'mkfs 会格式化文件系统，数据全部丢失'),
    (RegExp(r'\bdd\b[^|;]*\bof='), 'dd 直接写入块设备/文件，可能破坏数据'),
    (RegExp(r'\bwipe\b'), 'wipe 会清除数据'),
    (RegExp(r'\bformat\b'), 'format 会格式化存储'),
    (RegExp(r'\breboot\b'), 'reboot 会重启设备'),
    (RegExp(r'\bshutdown\b'), 'shutdown 会关机'),
    (RegExp(r'\bmount\b[^|;]*\bremount\b'), '重新挂载系统分区为可写，可能破坏系统'),
    (RegExp(r'>\s*/system'), '尝试写入 /system 分区'),
    (RegExp(r'>\s*/data/(?!data/com\.dsh)'), '尝试写入 /data 分区'),
    (RegExp(r'\bchmod\b[^|;]*\b777\b\s*/'), '对根路径设置 777 权限，严重削弱系统安全性'),
    (RegExp(r'\bsu\b\s+-?c?\b'), '尝试提权到 root'),
    (RegExp(r'\bsetenforce\b'), '切换 SELinux 模式，会削弱系统安全策略'),
    (RegExp(r'\bpm\s+uninstall-system-updates\b'), '卸载系统更新，可能导致系统不稳定'),
    (RegExp(r'\bappops\s+set\b'), '修改应用权限策略'),
    (RegExp(r'\bkillall\b'), '批量结束进程'),
  ];

  /// 会改变状态但通常可逆 —— 至少 caution。
  /// 用来给提示语提供更具体的解释。
  static final List<(RegExp, String)> _cautionPatterns =
      <(RegExp, String)>[
    (RegExp(r'\bpm\s+install\b'), '安装应用'),
    (RegExp(r'\bpm\s+(grant|revoke)\b'), '授予/撤销运行时权限'),
    (RegExp(r'\bsettings\s+(put|delete)\b'), '修改系统设置项'),
    (RegExp(r'\bsvc\s+\w+'), '切换系统服务（如 WiFi、数据网络）'),
    (RegExp(r'\bam\s+(start|force-stop|kill)\b'), '启动或强制停止应用'),
    (RegExp(r'\binput\s+(tap|swipe|keyevent|text)\b'), '模拟用户输入（点击/滑动/按键）'),
    (RegExp(r'\bsetprop\b'), '修改系统属性'),
    (RegExp(r'\bscreencap\b'), '截取屏幕内容'),
    (RegExp(r'\bscreenrecord\b'), '录制屏幕内容'),
    (RegExp(r'\bchmod\b'), '修改文件权限'),
    (RegExp(r'\bchown\b'), '修改文件属主'),
    (RegExp(r'\bmv\b'), '移动/重命名文件'),
    (RegExp(r'\bcp\b'), '复制文件'),
    (RegExp(r'\bmkdir\b'), '创建目录'),
    (RegExp(r'\btouch\b'), '创建或修改文件时间戳'),
    (RegExp(r'\bln\b'), '创建链接'),
    (RegExp(r'\bkill\b'), '结束进程'),
    (RegExp(r'\bpm\s+(hide|unhide|suspend)\b'), '隐藏/挂起应用'),
  ];

  /// 引号感知地把命令切成多段（按 `;` `&&` `||` `|` 和换行）。
  static List<String> splitSegments(String command) {
    final List<String> segments = <String>[];
    final StringBuffer buf = StringBuffer();
    String? quote;

    for (int i = 0; i < command.length; i++) {
      final String c = command[i];

      if (quote != null) {
        buf.write(c);
        if (c == quote) quote = null;
        continue;
      }

      if (c == "'" || c == '"') {
        quote = c;
        buf.write(c);
        continue;
      }

      if (c == '\\' && i + 1 < command.length) {
        buf.write(c);
        buf.write(command[i + 1]);
        i++;
        continue;
      }

      if (c == ';' || c == '\n') {
        segments.add(buf.toString());
        buf.clear();
        continue;
      }

      if ((c == '&' || c == '|') && i + 1 < command.length && command[i + 1] == c) {
        segments.add(buf.toString());
        buf.clear();
        i++;
        continue;
      }

      if (c == '|') {
        segments.add(buf.toString());
        buf.clear();
        continue;
      }

      buf.write(c);
    }

    segments.add(buf.toString());
    return segments
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
  }

  /// 去掉引号，避免引号内的内容干扰关键词匹配
  static String _stripQuotes(String s) =>
      s.replaceAll(RegExp(r'''["']'''), '');

  /// 去掉前置的环境变量赋值（`FOO=bar cmd`）
  static String _stripEnvPrefix(String segment) {
    String s = segment;
    while (true) {
      final RegExpMatch? m =
          RegExp(r'^(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)+').firstMatch(s);
      if (m == null) return s;
      s = s.substring(m.end);
    }
  }

  static bool _isSafeSegment(String segment) {
    final String s = _stripEnvPrefix(segment.trim());
    if (s.isEmpty) return true;

    // 含输出重定向就不是纯只读了（写文件）
    if (RegExp(r'(^|[^0-9>])>{1,2}[^&]').hasMatch(s)) return false;
    // 命令替换 / 子 shell 一律不认为是安全的
    if (s.contains('`') || s.contains(r'$(')) return false;
    // find 的 -delete / -exec 能造成破坏
    if (RegExp(r'\bfind\b').hasMatch(s) &&
        (s.contains('-delete') || s.contains('-exec'))) {
      return false;
    }
    // xargs 会把管道内容当作命令执行
    if (RegExp(r'\bxargs\b').hasMatch(s)) return false;

    final String bare = _stripQuotes(s);
    for (final RegExp re in _safePrefixes) {
      if (re.hasMatch(bare)) return true;
    }
    return false;
  }

  /// 评估一条 shell 命令
  static RiskAssessment assessShell(String command) {
    final String cmd = command.trim();
    if (cmd.isEmpty) {
      return const RiskAssessment(RiskLevel.caution, <String>['命令为空']);
    }

    final List<String> segments = splitSegments(cmd);
    if (segments.isEmpty) {
      return const RiskAssessment(RiskLevel.caution, <String>['命令为空']);
    }

    final List<String> reasons = <String>[];
    RiskLevel level = RiskLevel.safe;

    // 危险特征：在**整条命令**上匹配，因为跨管道也可能成立
    final String bare = _stripQuotes(cmd);
    for (final (RegExp re, String why) in _dangerousPatterns) {
      if (re.hasMatch(bare)) {
        level = RiskLevel.dangerous;
        reasons.add(why);
      }
    }

    // 逐段判断
    for (final String seg in segments) {
      final String segBare = _stripQuotes(seg);

      if (!_isSafeSegment(seg)) {
        if (level == RiskLevel.safe) level = RiskLevel.caution;
      }

      for (final (RegExp re, String why) in _cautionPatterns) {
        if (re.hasMatch(segBare)) {
          if (level == RiskLevel.safe) level = RiskLevel.caution;
          if (!reasons.contains(why)) reasons.add(why);
        }
      }
    }

    // 多段命令：段数越多越难一眼看全，至少 caution
    if (segments.length > 1 && level == RiskLevel.safe) {
      // 各段都安全时仍保持 safe（例如 dumpsys battery | grep level）
    }

    if (level == RiskLevel.caution && reasons.isEmpty) {
      reasons.add('包含无法确认为只读的操作，请自行核对命令内容');
    }

    if (level == RiskLevel.safe) {
      return RiskAssessment.safe;
    }

    return RiskAssessment(level, reasons);
  }

  /// 非 shell 类工具的通用评估：默认谨慎
  static RiskAssessment assessGeneric({
    required RiskLevel level,
    required List<String> reasons,
  }) {
    if (level == RiskLevel.safe) return RiskAssessment.safe;
    return RiskAssessment(level, reasons);
  }
}
