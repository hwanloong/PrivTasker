import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/store.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'home_shell.dart';

/// 工作空间：所有工作文件的存放目录。
///
/// ## 落在这里的是什么
///
/// 截图、录屏、聊天附件、插件脚本 —— 也就是**「工作」的中间产物和产物**。
///
/// ## 刻意**不**在这里的是什么
///
/// 会话记录、笔记、任务、设置、记忆、规则。它们仍然在应用私有目录
/// （`/data/data/<包名>/` 或应用专属的外部目录）。
///
/// 这个分界是有意的：工作文件是"可以随便看、随便删"的东西，放到用户
/// 能直接打开的位置是好事；而应用数据是"状态"，扔进用户可写目录等于
/// 把数据放在谁都能改的地方 —— 一次误删就全没了。
class WorkspacePage extends StatefulWidget {
  const WorkspacePage({
    super.key,
    required this.settings,
    required this.defaultWorkDir,
  });

  final Settings settings;

  /// 用户没指定时实际用的目录。要显示出来，否则用户不知道"默认"是哪。
  final String defaultWorkDir;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  /// 上一次校验的结果：null = 没校验过，空串 = 通过，否则是失败原因。
  String? _probeError;
  bool _probing = false;

  String get _current {
    final String p = widget.settings.workspacePath.trim();
    return p.isEmpty ? widget.defaultWorkDir : p;
  }

  bool get _isDefault => widget.settings.workspacePath.trim().isEmpty;

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);

    return Scaffold(
      backgroundColor: s.isDark ? AppColors.darkBg : AppColors.lightBg,
      body: Column(
        children: <Widget>[
          AppHeader(
            title: '工作空间',
            subtitle: _isDefault ? '默认位置' : '自定义位置',
            leading: GlassIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              tooltip: '返回',
              size: 38,
              iconSize: 19,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
              children: <Widget>[
                // ---- 当前目录 ----
                SurfaceCard(
                  padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(Icons.folder_outlined, size: 16, color: s.muted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '当前工作目录',
                              style: AppFonts.body(
                                  size: 12.5, color: s.muted, height: 1.3),
                            ),
                          ),
                          if (!_isDefault)
                            GlassChip(
                              label: '自定义',
                              color: AppColors.accent,
                              dense: true,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        _current,
                        style: AppFonts.code(size: 12.5, color: s.text),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ---- 校验结果 ----
                if (_probeError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SurfaceCard(
                      color: (_probeError!.isEmpty
                              ? AppColors.success
                              : AppColors.danger)
                          .withValues(alpha: 0.10),
                      borderColor: (_probeError!.isEmpty
                              ? AppColors.success
                              : AppColors.danger)
                          .withValues(alpha: 0.30),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(
                            _probeError!.isEmpty
                                ? Icons.check_circle_outline_rounded
                                : Icons.error_outline_rounded,
                            size: 17,
                            color: _probeError!.isEmpty
                                ? AppColors.success
                                : AppColors.danger,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              _probeError!.isEmpty
                                  ? '这个目录可以读写，已经在用了。'
                                  : '这个目录用不了：$_probeError',
                              style: AppFonts.body(
                                  size: 12.5, color: s.text, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ---- 操作 ----
                Row(
                  children: <Widget>[
                    Expanded(
                      child: GlassButton(
                        label: _probing ? '检查中…' : '选择文件夹',
                        icon: Icons.drive_file_move_outline,
                        fontSize: 13,
                        expand: true,
                        onTap: _probing ? null : _pick,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: GlassButton(
                        label: '手动输入路径',
                        icon: Icons.edit_outlined,
                        fontSize: 13,
                        expand: true,
                        onTap: _probing ? null : _typeManually,
                      ),
                    ),
                    if (!_isDefault) ...<Widget>[
                      const SizedBox(width: 8),
                      Expanded(
                        child: GlassButton(
                          label: '恢复默认',
                          icon: Icons.restart_alt_rounded,
                          fontSize: 13,
                          expand: true,
                          onTap: () async {
                            await widget.settings.update(
                                () => widget.settings.workspacePath = '');
                            setState(() => _probeError = null);
                          },
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 18),

                // ---- 说明 ----
                Text(
                  '放在这里的',
                  style: AppFonts.body(
                      size: 13.5, weight: FontWeight.w600, color: s.text),
                ),
                const SizedBox(height: 5),
                mdText(
                  '截图、录屏、聊天附件、插件脚本 —— 也就是「工作」的产物和中间产物。',
                  style: AppFonts.body(size: 12.5, color: s.muted, height: 1.6),
                ),

                const SizedBox(height: 14),
                mdText(
                  '**不**放在这里的',
                  style: AppFonts.body(
                      size: 13.5, weight: FontWeight.w600, color: s.text),
                ),
                const SizedBox(height: 5),
                mdText(
                  '会话记录、笔记、任务、设置、记忆、规则仍然在应用私有目录里。\n'
                  '这个分界是有意的：工作文件可以随便看、随便删，放到你能直接打开的'
                  '位置是好事；而应用数据是"状态"，扔进谁都能改的目录，一次误删就全没了。',
                  style: AppFonts.body(size: 12.5, color: s.muted, height: 1.6),
                ),

                const SizedBox(height: 14),
                mdText(
                  '关于「默认位置」',
                  style: AppFonts.body(
                      size: 13.5, weight: FontWeight.w600, color: s.text),
                ),
                const SizedBox(height: 5),
                mdText(
                  '默认目录在 `/sdcard/Android/data/<包名>/files/dsh`。\n'
                  '选它是因为 `screenrecord` 是**以 shell 身份**落盘的，'
                  '而 shell 写不进应用的私有数据目录 —— 这个位置两边都能写。\n'
                  '缺点是它在文件管理器里常常是隐藏的。想自己翻截图，'
                  '就换到「下载」这类可见目录。',
                  style: AppFonts.body(size: 12.5, color: s.muted, height: 1.6),
                ),

                const SizedBox(height: 14),
                mdText(
                  '改完立即生效，之后所有工具都落到新目录。**不会自动搬运**已有的'
                  '旧文件 —— 需要的话自己去文件管理器里移。',
                  style: AppFonts.body(size: 12.5, color: s.muted, height: 1.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pick() async {
    String? path;
    String? err;

    try {
      path = await getDirectoryPath();
    } catch (e) {
      // 非主存储卷（典型是 SD 卡）会走到这里 —— file_selector 的 Android
      // 实现解析不出那种 URI 对应的真实路径，会抛出来。
      // 这不是使用者做错了什么，但必须告诉他还有「手动输入」这条路，
      // 否则他只会觉得"选文件夹这个按钮坏了"。
      err = '系统没能把这个目录解析成路径（常见于 SD 卡）：$e\n'
          '请改用「手动输入路径」。';
    }

    if (!mounted) return;
    if (err != null) {
      setState(() => _probeError = err);
      return;
    }
    if (path == null) return; // 用户取消

    await _apply(path);
  }

  Future<void> _typeManually() async {
    final TextEditingController c = TextEditingController(text: _current);
    final String? path = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('工作目录路径'),
        content: TextField(
          controller: c,
          autofocus: true,
          style: AppFonts.code(size: 13),
          decoration: const InputDecoration(
            hintText: '/storage/emulated/0/Download/PrivTasker',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(c.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    c.dispose();

    if (path == null || path.trim().isEmpty) return;
    await _apply(path.trim());
  }

  /// 先**真的写一次**再保存。
  ///
  /// 不校验的话会出现很糟的情况：用户填了一个不可写的路径（Android 11+
  /// 对 `Android/data` 以外的很多位置都限制写入），设置看起来保存成功了，
  /// 直到某次截图失败才发现 —— 那时他根本不会联想到是工作目录的问题。
  Future<void> _apply(String path) async {
    setState(() {
      _probing = true;
      _probeError = null;
    });

    final String? err = await _probe(path);

    if (!mounted) return;
    setState(() {
      _probing = false;
      _probeError = err ?? '';
    });

    // 校验没过就不保存 —— 留着一个用不了的路径比留着空的更糟。
    if (err == null) {
      await widget.settings.update(() => widget.settings.workspacePath = path);
    }
  }

  /// 返回 null 表示可写，否则是失败原因。
  static Future<String?> _probe(String path) async {
    try {
      final Directory dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final File probe = File('$path/.dsh_write_test');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return null;
    } catch (e) {
      return '$e';
    }
  }
}
