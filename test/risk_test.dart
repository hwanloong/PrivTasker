import 'package:dsh_agent/core/models.dart';
import 'package:dsh_agent/tools/risk.dart';
import 'package:flutter_test/flutter_test.dart';

/// 风险分级器是整个 app 的安全基线，必须有测试兜住。
/// 这里覆盖的是最容易写错的两类情形：
///   · 引号里的 `|` 不能被当成管道分隔符；
///   · 多段命令必须取最高风险，不能因为第一段安全就放行。
void main() {
  group('只读命令判为 safe', () {
    test('query 里带引号的管道符不会把命令切错', () {
      // 这正是预览图里那条命令：grep -E 'level|status' 的 | 在引号内
      final RiskAssessment r =
          RiskClassifier.assessShell("dumpsys battery | grep -E 'level|status'");
      expect(r.level, RiskLevel.safe);
    });

    test('常见的只读组合', () {
      const List<String> cmds = <String>[
        'ls -la /sdcard',
        'cat /proc/cpuinfo',
        'getprop ro.product.model',
        'pm list packages -3',
        'settings get system screen_brightness',
        'df -h',
        'pm list packages | grep netease',
      ];
      for (final String c in cmds) {
        expect(RiskClassifier.assessShell(c).level, RiskLevel.safe,
            reason: '应判为 safe：$c');
      }
    });
  });

  group('破坏性命令判为 dangerous', () {
    test('删除 / 卸载 / 清数据 / 格式化', () {
      const List<String> cmds = <String>[
        'rm -rf /sdcard/Download',
        'pm clear com.netease.cloudmusic',
        'pm uninstall com.example.app',
        'pm disable-user --user 0 com.example.app',
        'mkfs.ext4 /dev/block/sda1',
        'dd if=/dev/zero of=/dev/block/sda',
        'reboot',
      ];
      for (final String c in cmds) {
        expect(RiskClassifier.assessShell(c).level, RiskLevel.dangerous,
            reason: '应判为 dangerous：$c');
      }
    });

    test('危险命令的每条理由都要说清楚，供弹窗展示', () {
      final RiskAssessment r =
          RiskClassifier.assessShell('pm clear com.netease.cloudmusic');
      expect(r.reasons, isNotEmpty);
      expect(r.isDangerous, isTrue);
    });
  });

  group('多段命令取最高风险', () {
    test('前段只读 + 后段删除 ⇒ dangerous', () {
      final RiskAssessment r = RiskClassifier.assessShell('ls /sdcard; rm -rf /sdcard/x');
      expect(r.level, RiskLevel.dangerous);
    });

    test('用 && 连接时同样取最高', () {
      final RiskAssessment r =
          RiskClassifier.assessShell('ls /sdcard && rm -rf /sdcard/x');
      expect(r.level, RiskLevel.dangerous);
    });

    test('各段都只读时整体仍为 safe', () {
      final RiskAssessment r =
          RiskClassifier.assessShell('df -h | grep data');
      expect(r.level, RiskLevel.safe);
    });
  });

  group('fail-safe：认不出来的一律要确认', () {
    test('未知命令不是 safe', () {
      final RiskAssessment r = RiskClassifier.assessShell('some_unknown_tool --do-things');
      expect(r.level, isNot(RiskLevel.safe));
      expect(r.level.needsConfirm, isTrue);
    });

    test('命令替换与输出重定向都不算只读', () {
      expect(RiskClassifier.assessShell('cat \$(ls)').level,
          isNot(RiskLevel.safe));
      expect(RiskClassifier.assessShell('echo hi > /sdcard/a.txt').level,
          isNot(RiskLevel.safe));
    });

    test('xargs / find -delete 不放过', () {
      expect(RiskClassifier.assessShell('ls | xargs rm').level,
          isNot(RiskLevel.safe));
      expect(RiskClassifier.assessShell('find /sdcard -name "*.tmp" -delete').level,
          isNot(RiskLevel.safe));
    });

    test('空命令给 caution 而不是 safe', () {
      expect(RiskClassifier.assessShell('   ').level, RiskLevel.caution);
    });
  });

  group('引号感知切分', () {
    test('引号内的分号不切分', () {
      final List<String> segs =
          RiskClassifier.splitSegments("grep -E 'level;status' /x");
      expect(segs.length, 1);
    });

    test('引号外的分号会切分', () {
      final List<String> segs = RiskClassifier.splitSegments('ls /a; ls /b');
      expect(segs.length, 2);
    });
  });
}
