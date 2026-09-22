import 'dart:convert';
import 'dart:io';

import '../core/models.dart';
import 'risk.dart';
import 'tool.dart';

/// 通用 shell：所有能力的兜底，也是模型最常用的入口。
class ShellTool extends AgentTool {
  const ShellTool();

  @override
  String get name => 'run_shell';

  @override
  String get title => 'shell';

  @override
  String get description =>
      '在设备上以 shell（adb）身份执行一条命令并返回结果。'
      '可访问 pm / am / settings / dumpsys / screencap / svc / input 等系统命令。'
      '注意：命令以 shell 身份运行，破坏性操作不可撤销。'
      '只读命令会自动执行，其余会先请用户确认。';

  @override
  Map<String, dynamic> get parameters => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'command': <String, dynamic>{
            'type': 'string',
            'description': '要执行的完整 shell 命令',
          },
          'purpose': <String, dynamic>{
            'type': 'string',
            'description': '一句话说明这条命令做什么，会展示给用户帮助其判断',
          },
        },
        'required': <String>['command'],
      };

  @override
  RiskAssessment riskFor(Map<String, dynamic> args) =>
      RiskClassifier.assessShell(args.str('command'));

  @override
  String summarize(Map<String, dynamic> args) => args.str('command');

  @override
  Future<String> run(ToolContext ctx, Map<String, dynamic> args) async {
    final String cmd = args.str('command').trim();
    if (cmd.isEmpty) return '错误：command 不能为空';

    final r = await ctx.shizuku.exec(cmd, timeoutMs: 30000);
    final StringBuffer sb = StringBuffer();
    sb.writeln('exit=${r.code}');
    if (r.timedOut) sb.writeln('（执行超时，已强制终止）');
    sb.writeln('--- stdout ---');
    sb.writeln(clampOutput(r.stdout.trim().isEmpty ? '(空)' : r.stdout.trim()));
    if (r.stderr.trim().isNotEmpty) {
      sb.writeln('--- stderr ---');
      sb.writeln(clampOutput(r.stderr.trim()));
    }
    return sb.toString();
  }
}

/// 应用管理
class AppManagerTool extends AgentTool {
  const AppManagerTool();

  @override
  String get name => 'app_manage';

  @override
  String get title => '应用管理';

  @override
  String get description =>
      '管理已安装应用。action 取值：'
      'list（列出应用）、info（查看详情）、path（查看安装路径）、'
      'clear（清除全部数据，危险）、uninstall（卸载，危险）、'
      'disable（停用，危险）、enable（启用）、force_stop（强制停止）、'
      'install（从指定 apk 路径安装）。';

  @override
  Map<String, dynamic> get parameters => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'action': <String, dynamic>{
            'type': 'string',
            'enum': <String>[
              'list',
              'info',
              'path',
              'clear',
              'uninstall',
              'disable',
              'enable',
              'force_stop',
              'install',
            ],
            'description': '要执行的操作',
          },
          'package': <String, dynamic>{
            'type': 'string',
            'description': '目标包名，如 com.netease.cloudmusic',
          },
          'scope': <String, dynamic>{
            'type': 'string',
            'enum': <String>['user', 'system', 'all'],
            'description': 'list 时的范围，默认 user（第三方应用）',
          },
          'filter': <String, dynamic>{
            'type': 'string',
            'description': 'list 时按关键字过滤包名',
          },
          'apk_path': <String, dynamic>{
            'type': 'string',
            'description': 'install 时的 apk 文件路径',
          },
        },
        'required': <String>['action'],
      };

  @override
  RiskAssessment riskFor(Map<String, dynamic> args) {
    final String action = args.str('action');
    final String pkg = args.str('package');

    switch (action) {
      case 'clear':
        return RiskAssessment(RiskLevel.dangerous, <String>[
          'pm clear 会清除 $pkg 的全部数据（登录状态、本地文件、缓存），不可撤销',
        ]);
      case 'uninstall':
        return RiskAssessment(RiskLevel.dangerous, <String>[
          '卸载 $pkg，其数据会一并丢失',
        ]);
      case 'disable':
        return RiskAssessment(RiskLevel.dangerous, <String>[
          '停用 $pkg，可能导致相关功能或系统组件异常',
        ]);
      case 'install':
        return RiskAssessment(RiskLevel.caution, <String>['从 apk 安装应用']);
      case 'enable':
      case 'force_stop':
        return RiskAssessment(RiskLevel.caution, <String>[
          action == 'enable' ? '启用应用' : '强制停止应用（未保存的数据可能丢失）',
        ]);
      default:
        return RiskAssessment.safe;
    }
  }

  @override
  String summarize(Map<String, dynamic> args) {
    final String a = args.str('action');
    if (a == 'list') return '列出应用（${args.str('scope', fallback: 'user')}）';
    if (a == 'install') return '安装 ${args.str('apk_path')}';
    return '$a ${args.str('package')}';
  }

  @override
  Future<String> run(ToolContext ctx, Map<String, dynamic> args) async {
    final String action = args.str('action');
    final String pkg = args.str('package').trim();

    Future<String> exec(String cmd) async {
      final r = await ctx.shizuku.exec(cmd, timeoutMs: 60000);
      if (!r.ok && r.stderr.trim().isNotEmpty) {
        return 'exit=${r.code}\n${clampOutput(r.stderr.trim())}';
      }
      return clampOutput(r.output.trim());
    }

    switch (action) {
      case 'list':
        final String scope = args.str('scope', fallback: 'user');
        final String flag = switch (scope) {
          'system' => '-s',
          'all' => '',
          _ => '-3',
        };
        String out = await exec('pm list packages $flag');
        final String filter = args.str('filter').toLowerCase();
        if (filter.isNotEmpty) {
          out = out
              .split('\n')
              .where((String l) => l.toLowerCase().contains(filter))
              .join('\n');
        }
        final int count = out
            .split('\n')
            .where((String l) => l.trim().isNotEmpty)
            .length;
        return '共 $count 个：\n$out';

      case 'info':
        if (pkg.isEmpty) return '错误：缺少 package';
        return exec('dumpsys package $pkg');

      case 'path':
        if (pkg.isEmpty) return '错误：缺少 package';
        return exec('pm path $pkg');

      case 'clear':
        if (pkg.isEmpty) return '错误：缺少 package';
        return exec('pm clear $pkg');

      case 'uninstall':
        if (pkg.isEmpty) return '错误：缺少 package';
        return exec('pm uninstall $pkg');

      case 'disable':
        if (pkg.isEmpty) return '错误：缺少 package';
        return exec('pm disable-user --user 0 $pkg');

      case 'enable':
        if (pkg.isEmpty) return '错误：缺少 package';
        return exec('pm enable $pkg');

      case 'force_stop':
        if (pkg.isEmpty) return '错误：缺少 package';
        return exec('am force-stop $pkg');

      case 'install':
        final String apk = args.str('apk_path');
        if (apk.isEmpty) return '错误：缺少 apk_path';
        return exec('pm install -r ${shQuote(apk)}');

      default:
        return '错误：未知 action「$action」';
    }
  }
}

/// 文件读写。刻意用 base64 传输内容，避免引号/换行把命令拆坏。
class FileTool extends AgentTool {
  const FileTool();

  @override
  String get name => 'file_op';

  @override
  String get title => '文件';

  @override
  String get description =>
      '读写设备文件。action 取值：'
      'list（列目录）、read（读文件，text 或 base64）、write（写文件）、'
      'append（追加）、delete（删除，危险）、move、copy、mkdir、'
      'search（按文件名查找）、stat（查看属性）。'
      '以 shell 身份运行，可访问 /sdcard 与系统目录。';

  @override
  Map<String, dynamic> get parameters => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'action': <String, dynamic>{
            'type': 'string',
            'enum': <String>[
              'list',
              'read',
              'write',
              'append',
              'delete',
              'move',
              'copy',
              'mkdir',
              'search',
              'stat',
            ],
          },
          'path': <String, dynamic>{
            'type': 'string',
            'description': '目标路径，如 /sdcard/Download/a.txt',
          },
          'dest': <String, dynamic>{
            'type': 'string',
            'description': 'move / copy 的目标路径',
          },
          'content': <String, dynamic>{
            'type': 'string',
            'description': 'write / append 的文本内容',
          },
          'encoding': <String, dynamic>{
            'type': 'string',
            'enum': <String>['text', 'base64'],
            'description': 'read 时返回格式，默认 text',
          },
          'pattern': <String, dynamic>{
            'type': 'string',
            'description': 'search 的文件名匹配，如 *.log',
          },
        },
        'required': <String>['action', 'path'],
      };

  @override
  RiskAssessment riskFor(Map<String, dynamic> args) {
    final String action = args.str('action');
    final String path = args.str('path');

    switch (action) {
      case 'delete':
        return RiskAssessment(RiskLevel.dangerous, <String>[
          '删除 $path，删除后无法从回收站恢复',
        ]);
      case 'write':
      case 'append':
        return RiskAssessment(RiskLevel.caution, <String>[
          '写入或覆盖 $path',
        ]);
      case 'move':
      case 'copy':
        return RiskAssessment(RiskLevel.caution, <String>[
          '$action 文件：$path → ${args.str('dest')}',
        ]);
      case 'mkdir':
        return RiskAssessment(RiskLevel.caution, <String>['创建目录 $path']);
      default:
        return RiskAssessment.safe;
    }
  }

  @override
  String summarize(Map<String, dynamic> args) {
    final String a = args.str('action');
    return '$a ${args.str('path')}';
  }

  @override
  Future<String> run(ToolContext ctx, Map<String, dynamic> args) async {
    final String action = args.str('action');
    final String path = args.str('path').trim();
    if (path.isEmpty) return '错误：path 不能为空';

    Future<String> exec(String cmd) async {
      final r = await ctx.shizuku.exec(cmd, timeoutMs: 30000);
      if (!r.ok && r.stderr.trim().isNotEmpty) {
        return 'exit=${r.code}\n${clampOutput(r.stderr.trim())}';
      }
      return clampOutput(r.output.trim());
    }

    switch (action) {
      case 'list':
        return exec('ls -la ${shQuote(path)}');

      case 'read':
        if (args.str('encoding', fallback: 'text') == 'base64') {
          return exec('base64 ${shQuote(path)}');
        }
        return exec('cat ${shQuote(path)}');

      case 'write':
      case 'append':
        final String content = args.str('content');
        final String op = action == 'write' ? '>' : '>>';
        // 内容先 base64 编码，彻底避开引号、换行、$ 等特殊字符
        final String b64 = base64Encode(utf8.encode(content));
        return exec(
          "printf '%s' ${shQuote(b64)} | base64 -d $op ${shQuote(path)}",
        );

      case 'delete':
        return exec('rm -f ${shQuote(path)}');

      case 'move':
        final String dest = args.str('dest');
        if (dest.isEmpty) return '错误：缺少 dest';
        return exec('mv ${shQuote(path)} ${shQuote(dest)}');

      case 'copy':
        final String dest = args.str('dest');
        if (dest.isEmpty) return '错误：缺少 dest';
        return exec('cp -r ${shQuote(path)} ${shQuote(dest)}');

      case 'mkdir':
        return exec('mkdir -p ${shQuote(path)}');

      case 'search':
        final String pattern = args.str('pattern', fallback: '*');
        return exec('find ${shQuote(path)} -name ${shQuote(pattern)} 2>/dev/null');

      case 'stat':
        return exec('stat ${shQuote(path)}');

      default:
        return '错误：未知 action「$action」';
    }
  }
}

/// 系统设置
class SettingsTool extends AgentTool {
  const SettingsTool();

  @override
  String get name => 'system_settings';

  @override
  String get title => '系统设置';

  @override
  String get description =>
      '读写系统设置与开关。action 取值：'
      'get / put / list（操作 system|secure|global 命名空间）、'
      'brightness（屏幕亮度 0-255）、volume（音量）、'
      'wifi（开/关）、data（移动数据开关）、airplane（飞行模式）、'
      'rotate（自动旋转）。';

  @override
  Map<String, dynamic> get parameters => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'action': <String, dynamic>{
            'type': 'string',
            'enum': <String>[
              'get',
              'put',
              'list',
              'brightness',
              'volume',
              'wifi',
              'data',
              'airplane',
              'rotate',
            ],
          },
          'namespace': <String, dynamic>{
            'type': 'string',
            'enum': <String>['system', 'secure', 'global'],
            'description': '设置命名空间，默认 system',
          },
          'key': <String, dynamic>{
            'type': 'string',
            'description': 'get / put 时的设置项名',
          },
          'value': <String, dynamic>{
            'type': 'string',
            'description': 'put 时的值',
          },
          'level': <String, dynamic>{
            'type': 'integer',
            'description': 'brightness 用 0-255；volume 用 0-15',
          },
          'enabled': <String, dynamic>{
            'type': 'boolean',
            'description': '开关类操作的开关值',
          },
          'stream': <String, dynamic>{
            'type': 'integer',
            'description': 'volume 的音轨：0 通话 1 系统 2 铃声 3 媒体 4 闹钟',
          },
        },
        'required': <String>['action'],
      };

  @override
  RiskAssessment riskFor(Map<String, dynamic> args) {
    final String action = args.str('action');
    switch (action) {
      case 'get':
      case 'list':
        return RiskAssessment.safe;
      case 'wifi':
      case 'data':
      case 'airplane':
        return RiskAssessment(RiskLevel.caution, <String>[
          '切换网络开关会中断当前连接',
        ]);
      case 'brightness':
        return RiskAssessment(RiskLevel.caution, <String>['修改屏幕亮度']);
      case 'volume':
        return RiskAssessment(RiskLevel.caution, <String>['修改音量']);
      case 'rotate':
        return RiskAssessment(RiskLevel.caution, <String>['切换自动旋转']);
      case 'put':
        return RiskAssessment(RiskLevel.caution, <String>[
          '修改系统设置项 ${args.str('namespace', fallback: 'system')}/${args.str('key')}',
        ]);
      default:
        return RiskAssessment(RiskLevel.caution, <String>['未知的设置操作']);
    }
  }

  @override
  String summarize(Map<String, dynamic> args) {
    final String a = args.str('action');
    if (a == 'get' || a == 'put') {
      return '$a ${args.str('namespace', fallback: 'system')}/${args.str('key')}';
    }
    return a;
  }

  @override
  Future<String> run(ToolContext ctx, Map<String, dynamic> args) async {
    final String action = args.str('action');
    final String ns = args.str('namespace', fallback: 'system');

    Future<String> exec(String cmd) async {
      final r = await ctx.shizuku.exec(cmd, timeoutMs: 20000);
      if (!r.ok && r.stderr.trim().isNotEmpty) {
        return 'exit=${r.code}\n${clampOutput(r.stderr.trim())}';
      }
      return clampOutput(r.output.trim());
    }

    switch (action) {
      case 'get':
        final String key = args.str('key');
        if (key.isEmpty) return '错误：缺少 key';
        return exec('settings get $ns ${shQuote(key)}');

      case 'put':
        final String key = args.str('key');
        if (key.isEmpty) return '错误：缺少 key';
        return exec(
          'settings put $ns ${shQuote(key)} ${shQuote(args.str('value'))}',
        );

      case 'list':
        return exec('settings list $ns');

      case 'brightness':
        final int lv = args.intVal('level', fallback: -1);
        if (lv < 0 || lv > 255) return '错误：level 需在 0-255 之间';
        // 关掉自动亮度，否则改完会被系统立刻覆盖
        await ctx.shizuku.exec('settings put system screen_brightness_mode 0');
        return exec('settings put system screen_brightness $lv');

      case 'volume':
        final int stream = args.intVal('stream', fallback: 3);
        final int lv = args.intVal('level', fallback: -1);
        if (lv < 0) return '错误：缺少 level';
        return exec('cmd media volume --stream $stream --set $lv');

      case 'wifi':
        return exec('svc wifi ${args.boolVal('enabled') ? 'enable' : 'disable'}');

      case 'data':
        return exec('svc data ${args.boolVal('enabled') ? 'enable' : 'disable'}');

      case 'airplane':
        final bool on = args.boolVal('enabled');
        return exec(
          'settings put global airplane_mode_on ${on ? 1 : 0}; '
          'am broadcast -a android.intent.action.AIRPLANE_MODE --ez state $on',
        );

      case 'rotate':
        return exec(
          'settings put system accelerometer_rotation '
          '${args.boolVal('enabled') ? 1 : 0}',
        );

      default:
        return '错误：未知 action「$action」';
    }
  }
}

/// 截图 / 录屏
class CaptureTool extends AgentTool {
  const CaptureTool();

  @override
  String get name => 'screen_capture';

  @override
  String get title => '截屏录屏';

  @override
  String get description =>
      '截取屏幕或录制屏幕。action：'
      'screenshot（截图，返回保存路径，可用 read_image 继续识别内容）、'
      'record（录屏，需给 duration 秒数）。';

  @override
  Map<String, dynamic> get parameters => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'action': <String, dynamic>{
            'type': 'string',
            'enum': <String>['screenshot', 'record'],
          },
          'duration': <String, dynamic>{
            'type': 'integer',
            'description': '录屏时长（秒），默认 10，最长 180',
          },
        },
        'required': <String>['action'],
      };

  @override
  RiskAssessment riskFor(Map<String, dynamic> args) {
    // 截图/录屏本身不破坏数据，但会捕获屏幕上的隐私内容，所以要求确认。
    return RiskAssessment(RiskLevel.caution, <String>[
      args.str('action') == 'record'
          ? '会录制屏幕内容，可能包含隐私信息'
          : '会截取当前屏幕内容，可能包含隐私信息',
    ]);
  }

  @override
  String summarize(Map<String, dynamic> args) => args.str('action');

  @override
  Future<String> run(ToolContext ctx, Map<String, dynamic> args) async {
    final String action = args.str('action');
    await Directory(ctx.workDir).create(recursive: true);

    if (action == 'screenshot') {
      // binary=true：screencap -p 直接输出 PNG 字节流，走字符串会损坏数据
      final r = await ctx.shizuku.exec('screencap -p', binary: true);
      if (r.bytes == null || r.bytes!.isEmpty) {
        return '截图失败：未取得图像数据。${r.stderr}';
      }
      final String path =
          '${ctx.workDir}/shot_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(path).writeAsBytes(r.bytes!);
      return '截图已保存：$path\n（${r.bytes!.length} 字节，可继续用 read_image 识别其中文字）';
    }

    if (action == 'record') {
      final int dur = args.intVal('duration', fallback: 10).clamp(1, 180);
      final String path =
          '${ctx.workDir}/rec_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final r = await ctx.shizuku.exec(
        'screenrecord --time-limit $dur ${shQuote(path)}',
        timeoutMs: dur * 1000 + 8000,
      );
      final bool exists = await _existsViaShell(ctx, path);
      if (!exists) {
        return '录屏失败。exit=${r.code}\n${r.stderr}';
      }
      return '录屏已保存：$path（$dur 秒）';
    }

    return '错误：未知 action「$action」';
  }

  Future<bool> _existsViaShell(ToolContext ctx, String path) async {
    final r = await ctx.shizuku.exec('test -f ${shQuote(path)} && echo yes');
    return r.stdout.contains('yes');
  }
}
