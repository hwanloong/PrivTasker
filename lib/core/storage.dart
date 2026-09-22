import 'dart:io';

/// 存储占用报告
class StorageReport {
  const StorageReport({
    required this.shotCount,
    required this.shotBytes,
    required this.attachCount,
    required this.attachBytes,
    required this.otherCount,
    required this.otherBytes,
  });

  /// 截图与录屏
  final int shotCount;
  final int shotBytes;

  /// 聊天附件（图片、文件）
  final int attachCount;
  final int attachBytes;

  /// 其它残留
  final int otherCount;
  final int otherBytes;

  int get totalBytes => shotBytes + attachBytes + otherBytes;
  int get totalCount => shotCount + attachCount + otherCount;

  bool get isEmpty => totalCount == 0;

  static String human(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

/// 应用自己产生的文件的清点与清理。
///
/// 工作目录布局（`workDir` 是应用的外部私有目录）：
///   `shot_*.png`      截图（screen_capture 工具产出）
///   `rec_*.mp4`       录屏
///   `attachments/`    聊天附件（选图、选文件时复制进来）
///
/// 有一点必须提醒用户：**删掉 attachments 会让历史记录里的图片/文件失效**。
/// 消息本身还在，但附件会显示成破图。所以清理前要明确告知。
class StorageManager {
  const StorageManager._();

  static const String attachDirName = 'attachments';

  /// 这些前缀的文件算「截图与录屏」，可以安全删除（它们只是工具的中间产物）
  static bool _isCapture(String name) =>
      name.startsWith('shot_') || name.startsWith('rec_');

  static Future<StorageReport> scan(String workDir) async {
    int shotCount = 0, shotBytes = 0;
    int attachCount = 0, attachBytes = 0;
    int otherCount = 0, otherBytes = 0;

    final Directory root = Directory(workDir);
    if (!await root.exists()) {
      return const StorageReport(
        shotCount: 0,
        shotBytes: 0,
        attachCount: 0,
        attachBytes: 0,
        otherCount: 0,
        otherBytes: 0,
      );
    }

    try {
      await for (final FileSystemEntity e in root.list(recursive: true)) {
        if (e is! File) continue;
        final int size = await e.length();
        final String name = e.uri.pathSegments.last;

        if (e.path.contains('/$attachDirName/')) {
          attachCount++;
          attachBytes += size;
        } else if (_isCapture(name)) {
          shotCount++;
          shotBytes += size;
        } else {
          otherCount++;
          otherBytes += size;
        }
      }
    } catch (_) {
      // 目录被并发修改时忽略，返回已统计到的部分
    }

    return StorageReport(
      shotCount: shotCount,
      shotBytes: shotBytes,
      attachCount: attachCount,
      attachBytes: attachBytes,
      otherCount: otherCount,
      otherBytes: otherBytes,
    );
  }

  static Future<int> _deleteWhere(
    String workDir,
    bool Function(File file) match,
  ) async {
    int removed = 0;
    final Directory root = Directory(workDir);
    if (!await root.exists()) return 0;

    try {
      await for (final FileSystemEntity e in root.list(recursive: true)) {
        if (e is! File) continue;
        if (!match(e)) continue;
        try {
          await e.delete();
          removed++;
        } catch (_) {
          // 单个文件删不掉不影响其它
        }
      }
    } catch (_) {
      // 忽略目录遍历失败
    }
    return removed;
  }

  /// 删除截图与录屏。这些是工具的中间产物，删了不影响历史记录。
  static Future<int> clearCaptures(String workDir) {
    return _deleteWhere(workDir, (File f) {
      final String name = f.uri.pathSegments.last;
      return !f.path.contains('/$attachDirName/') && _isCapture(name);
    });
  }

  /// 删除聊天附件。
  ///
  /// 注意：历史消息里对这些文件的引用会失效（显示成破图），
  /// 消息本身和文本内容不受影响。
  static Future<int> clearAttachments(String workDir) {
    return _deleteWhere(workDir, (File f) {
      return f.path.contains('/$attachDirName/');
    });
  }

  /// 清空整个工作目录
  static Future<int> clearAll(String workDir) async {
    int removed = 0;
    final Directory root = Directory(workDir);
    if (!await root.exists()) return 0;

    try {
      await for (final FileSystemEntity e in root.list()) {
        try {
          await e.delete(recursive: true);
          removed++;
        } catch (_) {
          // 忽略
        }
      }
    } catch (_) {
      // 忽略
    }
    return removed;
  }

  /// 自动清理超过 [olderThan] 的截图与录屏。
  ///
  /// 这两类是工具的**中间产物**（给模型看完就没用了），历史记录不引用它们，
  /// 所以可以放心按时间自动清理，不需要每次都问用户。
  /// 聊天附件不在此列 —— 那是用户自己发的内容，只在用户明确要求时才删。
  static Future<int> clearOldCaptures(
    String workDir,
    Duration olderThan,
  ) async {
    final DateTime cutoff = DateTime.now().subtract(olderThan);
    return _deleteWhere(workDir, (File f) {
      final String name = f.uri.pathSegments.last;
      if (f.path.contains('/$attachDirName/')) return false;
      if (!_isCapture(name)) return false;
      try {
        return f.statSync().modified.isBefore(cutoff);
      } catch (_) {
        return false;
      }
    });
  }
}
