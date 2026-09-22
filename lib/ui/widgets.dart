import 'dart:io';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'browser_page.dart';
import 'markdown.dart';

/// 渲染一条消息。
///
/// 用户消息是蓝色气泡；**assistant 消息没有气泡**，Markdown 直接平铺在背景上。
class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.message,
    this.onOpenLink,
  });

  final ChatMessage message;
  final void Function(String url)? onOpenLink;

  @override
  Widget build(BuildContext context) {
    if (message.role == Role.user) {
      return _userBubble(context);
    }
    return _assistantBlock(context);
  }

  Widget _userBubble(BuildContext context) {
    final AppSurface s = AppSurface.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6, left: 44),
      child: Align(
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            if (message.attachments.isNotEmpty &&
                message.content.trim().isNotEmpty)
              const SizedBox(height: 2),
            if (message.content.trim().isNotEmpty)
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(19),
                    topRight: Radius.circular(19),
                    bottomLeft: Radius.circular(19),
                    bottomRight: Radius.circular(6),
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: SelectableText(
                  message.content,
                  style: AppFonts.body(
                    size: 15,
                    color: Colors.white,
                    height: 1.6,
                  ),
                ),
              ),
            if (message.attachments.isNotEmpty)
              _attachmentStrip(context, s),
          ],
        ),
      ),
    );
  }

  /// 用户消息里的附件：图片显示缩略图，网页显示可展开的卡片，
  /// 其它文件显示文件名。
  Widget _attachmentStrip(BuildContext context, AppSurface s) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, right: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: message.attachments
            .where((Attachment a) => a.kind == AttachmentKind.web)
            .map((Attachment a) => _webCard(context, s, a))
            .toList()
          ..addAll(
            message.attachments
                .where((Attachment a) => a.kind != AttachmentKind.web)
                .map((Attachment a) => Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: _mediaCard(context, s, a),
                    )),
          ),
      ),
    );
  }

  /// 网页附件卡片：标题 + 域名 + 内容预览，可展开、可在内置浏览器打开
  Widget _webCard(BuildContext context, AppSurface s, Attachment a) {
    final int len = a.content.trim().length;
    final String host = _hostOf(a.path);
    final String preview = a.content.trim().isEmpty
        ? '（没有抓到内容，只有链接）'
        : (len > 420 ? '${a.content.trim().substring(0, 420)}…' : a.content.trim());

    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: SurfaceCard(
          padding: const EdgeInsets.fromLTRB(13, 11, 13, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.public_rounded,
                      size: 15, color: AppColors.accent),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      a.name.isEmpty ? host : a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.body(
                        size: 13,
                        weight: FontWeight.w600,
                        color: s.text,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.code(size: 11, color: s.muted),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 260),
                decoration: BoxDecoration(
                  color: s.codeBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                child: SingleChildScrollView(
                  child: Text(
                    preview,
                    style: AppFonts.code(size: 11.5, color: s.text),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  if (len > 0)
                    GlassChip(
                      label: '$len 字符',
                      dense: true,
                      color: s.muted,
                    ),
                  const Spacer(),
                  GlassButton(
                    label: '内嵌预览',
                    icon: Icons.open_in_browser_rounded,
                    fontSize: 12,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 6),
                    onTap: () =>
                        BrowserPage.open(context, url: a.path, title: a.name),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _hostOf(String url) {
    final Uri? u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return url;
    return u.host;
  }

  Widget _mediaCard(BuildContext context, AppSurface s, Attachment a) {
    if (a.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(
          File(a.path),
          width: 150,
          height: 150,
          fit: BoxFit.cover,
          errorBuilder: (BuildContext _, Object _, StackTrace? _) => Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: s.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: s.border, width: 0.9),
            ),
            child: Center(
              child:
                  Icon(Icons.broken_image_outlined, size: 22, color: s.muted),
            ),
          ),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: s.border, width: 0.9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.description_outlined, size: 15, color: s.muted),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              a.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.body(size: 12.5, color: s.text, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _assistantBlock(BuildContext context) {
    final AppSurface s = AppSurface.of(context);
    final List<Widget> children = <Widget>[];

    if (message.content.trim().isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: MarkdownView(
            text: message.content,
            baseSize: 15,
            onOpenLink: onOpenLink,
          ),
        ),
      );
    }

    for (final ToolInvocation inv in message.tools) {
      children.add(ToolCallCard(invocation: inv));
    }

    if (message.error != null && message.error!.trim().isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SurfaceCard(
            color: AppColors.danger.withValues(alpha: 0.08),
            borderColor: AppColors.danger.withValues(alpha: 0.3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.error_outline_rounded,
                    size: 17, color: AppColors.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message.error!,
                    style: AppFonts.body(
                      size: 13.5,
                      color: AppColors.danger,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 流式输出时的光标
    if (message.pending && message.content.trim().isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: s.muted,
              ),
            ),
            const SizedBox(width: 9),
            Text('思考中…',
                style: AppFonts.body(size: 13.5, color: s.muted, height: 1.3)),
          ],
        ),
      ));
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// 一次工具调用的卡片：工具名 / 风险标签 / 具体命令 / 执行结果
class ToolCallCard extends StatelessWidget {
  const ToolCallCard({super.key, required this.invocation});

  final ToolInvocation invocation;

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);
    final RiskLevel level = invocation.risk.level;

    final (Color color, String tag) = switch (invocation.status) {
      InvocationStatus.awaitingConfirm => (AppColors.warning, '等待确认'),
      InvocationStatus.running => (AppColors.accent, '执行中'),
      InvocationStatus.rejected => (AppColors.danger, '已拒绝'),
      InvocationStatus.failed => (AppColors.danger, '失败'),
      InvocationStatus.success => switch (level) {
          RiskLevel.safe => (AppColors.success, '只读 · 自动执行'),
          RiskLevel.caution => (AppColors.success, '已确认执行'),
          RiskLevel.dangerous => (AppColors.danger, '危险 · 已确认'),
        },
    };

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  invocation.name,
                  style: AppFonts.body(
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: s.text,
                    height: 1.2,
                  ),
                ),
                const SizedBox(width: 8),
                GlassChip(
                  label: tag,
                  color: color,
                  background: color.withValues(alpha: 0.12),
                  dense: true,
                ),
                const Spacer(),
                if (invocation.status == InvocationStatus.running)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: s.muted,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 9),
            _commandBox(s),
            if (invocation.risk.reasons.isNotEmpty &&
                invocation.status != InvocationStatus.success)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: invocation.risk.reasons
                      .map((String r) => Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text('· ',
                                    style: AppFonts.body(
                                        size: 12.5, color: color, height: 1.5)),
                                Expanded(
                                  child: Text(
                                    r,
                                    style: AppFonts.body(
                                      size: 12.5,
                                      color: s.muted,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),
            if (invocation.output != null &&
                invocation.output!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (invocation.status == InvocationStatus.success)
                      const Padding(
                        padding: EdgeInsets.only(top: 1.5),
                        child: Icon(Icons.check_rounded,
                            size: 14, color: AppColors.success),
                      ),
                    if (invocation.status == InvocationStatus.success)
                      const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _clip(invocation.output!),
                        style: AppFonts.code(
                          size: 12.3,
                          color: invocation.status == InvocationStatus.rejected
                              ? s.muted
                              : s.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _clip(String s) {
    final String t = s.trim();
    if (t.length <= 1500) return t;
    return '${t.substring(0, 1500)}\n…（已截断）';
  }

  Widget _commandBox(AppSurface s) {
    final String text = _displayCommand();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: s.codeBg,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: SelectableText(
        text,
        style: AppFonts.code(size: 12.4, color: s.text),
      ),
    );
  }

  String _displayCommand() {
    final Map<String, dynamic> a = invocation.args;
    if (a.containsKey('command')) return a['command'].toString();
    if (a.containsKey('action') && a.containsKey('path')) {
      return '${a['action']} ${a['path']}';
    }
    if (a.containsKey('action')) {
      final String pkg = a['package']?.toString() ?? '';
      return pkg.isEmpty
          ? a['action'].toString()
          : '${a['action']} $pkg';
    }
    if (a.containsKey('query')) return '搜索：${a['query']}';
    return invocation.argumentsJson;
  }
}

/// 危险操作确认弹窗。返回 true 表示放行。
///
/// 危险等级的操作，默认焦点给「拒绝」——避免误触就执行了不可撤销的命令。
Future<bool> showRiskConfirmDialog(
  BuildContext context, {
  required ToolInvocation invocation,
  required String toolTitle,
}) async {
  final AppSurface s = AppSurface.of(context);
  final bool dangerous = invocation.risk.isDangerous;

  final bool? result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext ctx) {
      return AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        actionsPadding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
        title: Row(
          children: <Widget>[
            Icon(
              dangerous
                  ? Icons.warning_amber_rounded
                  : Icons.help_outline_rounded,
              color: dangerous ? AppColors.danger : AppColors.warning,
              size: 21,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                dangerous ? '危险操作确认' : '操作确认',
                style: AppFonts.body(
                  size: 16.5,
                  weight: FontWeight.w700,
                  color: s.text,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '$toolTitle 请求执行以下内容：',
                style: AppFonts.body(size: 12.8, color: s.muted, height: 1.55),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: s.codeBg,
                  borderRadius: BorderRadius.circular(11),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                child: SelectableText(
                  invocation.args['command']?.toString() ??
                      invocation.argumentsJson,
                  style: AppFonts.code(size: 12.4, color: s.text),
                ),
              ),
              if (invocation.risk.reasons.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                ...invocation.risk.reasons.map(
                  (String r) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.circle,
                            size: 5,
                            color: dangerous
                                ? AppColors.danger
                                : AppColors.warning,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            r,
                            style: AppFonts.body(
                              size: 12.6,
                              color: s.text,
                              height: 1.55,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                '该内容由 AI 自动生成，不是你自己输入的。请核对后再决定。',
                style: AppFonts.body(size: 12, color: s.muted, height: 1.5),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: GlassButton(
                  label: '拒绝',
                  expand: true,
                  onTap: () => Navigator.of(ctx).pop(false),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: GlassButton(
                  label: dangerous ? '仍然执行' : '执行',
                  expand: true,
                  danger: dangerous,
                  accent: !dangerous,
                  onTap: () => Navigator.of(ctx).pop(true),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );

  return result ?? false;
}
