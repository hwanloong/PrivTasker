import 'package:flutter/material.dart';

import '../core/storage.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';

Future<void> showStorageSheet(
  BuildContext context, {
  required String workDir,
  VoidCallback? onCleared,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext ctx) =>
        _StorageSheet(workDir: workDir, onCleared: onCleared),
  );
}

class _StorageSheet extends StatefulWidget {
  const _StorageSheet({required this.workDir, this.onCleared});

  final String workDir;
  final VoidCallback? onCleared;

  @override
  State<_StorageSheet> createState() => _StorageSheetState();
}

class _StorageSheetState extends State<_StorageSheet> {
  StorageReport? _report;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final StorageReport r = await StorageManager.scan(widget.workDir);
    if (mounted) setState(() => _report = r);
  }

  Future<void> _run(
    Future<int> Function() action, {
    required String what,
    String? warning,
  }) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(
          '删除$what？',
          style: AppFonts.body(size: 16.5, weight: FontWeight.w700, height: 1.3),
        ),
        content: Text(
          warning ?? '删除后无法恢复。',
          style: AppFonts.body(size: 13.5, height: 1.6),
        ),
        actions: <Widget>[
          GlassButton(label: '取消', onTap: () => Navigator.of(ctx).pop(false)),
          GlassButton(
            label: '删除',
            danger: true,
            onTap: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    final int n = await action();
    await _refresh();
    widget.onCleared?.call();
    if (!mounted) return;
    setState(() => _busy = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除 $n 项'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);
    final StorageReport? r = _report;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
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
                  '存储空间',
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
            child: r == null
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 50),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: <Widget>[
                      // 总览
                      SurfaceCard(
                        margin: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.folder_outlined,
                                size: 19, color: AppColors.accent),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    r.isEmpty
                                        ? '没有占用'
                                        : StorageReport.human(r.totalBytes),
                                    style: AppFonts.body(
                                      size: 18,
                                      weight: FontWeight.w700,
                                      color: s.text,
                                      height: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    r.isEmpty
                                        ? '应用还没有产生任何文件'
                                        : '共 ${r.totalCount} 个文件',
                                    style: AppFonts.body(
                                        size: 12,
                                        color: s.muted,
                                        height: 1.3),
                                  ),
                                ],
                              ),
                            ),
                            if (!r.isEmpty && !_busy)
                              GlassButton(
                                label: '全部清理',
                                danger: true,
                                fontSize: 12.5,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 13, vertical: 8),
                                onTap: () => _run(
                                  () => StorageManager.clearAll(widget.workDir),
                                  what: '全部文件',
                                  warning: '会清空应用产生的所有文件：'
                                      '截图、录屏、以及聊天里的图片和附件。\n\n'
                                      '历史消息还在，但里面的图片和附件会显示不出来。\n\n'
                                      '此操作无法撤销。',
                                ),
                              ),
                          ],
                        ),
                      ),

                      _row(
                        s,
                        icon: Icons.photo_camera_outlined,
                        title: '截图与录屏',
                        desc: '工具产生的中间文件，删除不影响历史记录',
                        count: r.shotCount,
                        bytes: r.shotBytes,
                        onDelete: () => _run(
                          () => StorageManager.clearCaptures(widget.workDir),
                          what: '截图与录屏',
                        ),
                      ),
                      _row(
                        s,
                        icon: Icons.attachment_outlined,
                        title: '聊天附件',
                        desc: '你发送的图片和文件。删除后历史消息里的它们会显示不出来',
                        count: r.attachCount,
                        bytes: r.attachBytes,
                        onDelete: () => _run(
                          () => StorageManager.clearAttachments(widget.workDir),
                          what: '聊天附件',
                          warning: '这些是你之前发过的图片和文件。\n\n'
                              '删除后，历史消息里的附件会变成破图（文字内容不受影响），'
                              '而且无法恢复。\n\n'
                              '如果想让历史记录也一并干净，可以到「历史记录」里先清空会话。',
                        ),
                      ),
                      if (r.otherCount > 0)
                        _row(
                          s,
                          icon: Icons.help_outline_rounded,
                          title: '其它文件',
                          desc: '不属于以上分类的残留文件',
                          count: r.otherCount,
                          bytes: r.otherBytes,
                          onDelete: null,
                        ),

                      const SizedBox(height: 6),
                      Text(
                        '工作目录：${widget.workDir}',
                        style: AppFonts.code(size: 10.5, color: s.muted),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    AppSurface s, {
    required IconData icon,
    required String title,
    required String desc,
    required int count,
    required int bytes,
    VoidCallback? onDelete,
  }) {
    final bool empty = count == 0;

    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: empty ? s.muted : AppColors.accent),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: AppFonts.body(
                          size: 14,
                          weight: FontWeight.w600,
                          color: s.text,
                          height: 1.3,
                        ),
                      ),
                    ),
                    Text(
                      empty ? '—' : StorageReport.human(bytes),
                      style: AppFonts.code(
                        size: 12.5,
                        color: empty ? s.muted : s.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  empty ? '暂无文件' : '$count 个 · $desc',
                  style: AppFonts.body(size: 12, color: s.muted, height: 1.45),
                ),
              ],
            ),
          ),
          if (!empty && onDelete != null && !_busy)
            IconButton(
              icon: Icon(Icons.delete_outline_rounded,
                  size: 18, color: AppColors.danger),
              tooltip: '删除',
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}
