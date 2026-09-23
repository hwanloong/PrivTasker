import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'browser_page.dart';
import 'markdown.dart';
import 'tool_line.dart';

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
                decoration: BoxDecoration(
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
                  Icon(Icons.public_rounded,
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
                  borderRadius: BorderRadius.circular(AppRadius.code),
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
        borderRadius: BorderRadius.circular(AppRadius.field),
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
              borderRadius: BorderRadius.circular(AppRadius.field),
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
        borderRadius: BorderRadius.circular(AppRadius.field),
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
            // 流式期间不渲染卡片。InAppWebView 的 initialData **只在创建时读一次**，
            // 所以流式中途创建的 WebView 拿到的是半截 HTML，之后又不会重载 ——
            // 表现为"卡片不显示，重启应用才出现"。
            // 关掉后，未完成的卡片先显示成代码块，流式结束才切成卡片，
            // 那时 WebView 才第一次创建，拿到的就是完整内容。
            enableCards: !message.pending,
          ),
        ),
      );

      // 复制按钮。
      //
      // 为什么需要它：markdown 是用**裸 RichText** 渲染的，而 Flutter 的
      // SelectionArea 只对 Text 组件生效 —— 裸 RichText 不会注册到选择系统，
      // 所以正文根本选不中。与其把整个渲染器改成 Text.rich（改动面大、
      // 还容易在表格/代码块里出岔子），不如直接给一个可靠的复制入口。
      //
      // 流式输出中不显示：复制一段还在增长的内容没有意义。
      if (!message.pending) {
        children.add(_CopyButton(text: message.content));
      }

      // 正文里出现网址时，在下面补一排卡片 ——
      // 一眼能看出是网页还是 API，也能直接点开。
      if (!message.pending) {
        children.add(
          LinkCards(text: message.content, onOpen: onOpenLink),
        );
      }
    }

    for (final ToolInvocation inv in message.tools) {
      // 一行式显示，点开才展开参数和输出。
      // 原来的展开卡片会把正文挤到看不见，而多数时候用户只想确认
      // "它干了什么"，不想看输入输出的完整原文。
      children.add(ToolLine(invocation: inv));
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
/// 复制 AI 回复的原文（Markdown 源码，不是渲染后的纯文本）。
///
/// 复制**原文**而不是渲染结果：用户复制多半是要粘到别处继续用，
/// 这时保留 `##`、`-`、代码围栏才是有用的；渲染后的纯文本会丢掉结构。
/// 从 AI 回复的正文里找出网址，渲染成卡片。
///
/// 为什么需要：模型引用来源时通常把 URL 直接写进正文，markdown 渲染出来
/// 就是一串蓝色的字。**看不出那是网页还是 API 接口，也没法一键打开。**
///
/// 这里做两件事：
///  1. 把网址提出来做成可点的卡片（直接在内置浏览器打开）
///  2. **区分「网页」和「API 接口」** —— 图标、配色、标签都不同。
///     模型给出 API 地址时，用户想的是"抓一份数据看看"，
///     而不是"用浏览器打开它"。
class LinkCards extends StatelessWidget {
  const LinkCards({super.key, required this.text, this.onOpen});

  final String text;
  final void Function(String url)? onOpen;

  /// 最多渲染几张。模型有时一口气列十几个来源，
  /// 全铺开会把正文彻底淹没 —— 那还不如不给卡片。
  static const int _maxCards = 4;

  /// 用三引号原始字符串：URL 里可能出现的 `'` 和反引号混在普通引号里很容易写错。
  static final RegExp _urlRe = RegExp(
    r'''https?://[^\s<>()\[\]"'`]+''',
    caseSensitive: false,
  );

  /// 提取去重后的网址
  static List<String> extract(String text) {
    final Set<String> seen = <String>{};
    final List<String> out = <String>[];
    for (final RegExpMatch m in _urlRe.allMatches(text)) {
      String u = m.group(0)!;
      // 去掉尾部粘连的标点：`见 https://a.com。` 这种在中文里非常常见
      u = u.replaceAll(RegExp(r'[.,;:!?，。；：！？、）】»]+$'), '');
      if (u.length < 12) continue;
      if (seen.add(u)) out.add(u);
      if (out.length >= _maxCards) break;
    }
    return out;
  }

  /// 判断是 API 接口而不是网页。
  ///
  /// 用启发式规则而不是发请求探测 —— 探测要花时间，而这里只决定图标长什么样，
  /// 猜错的代价很小。**宁可快。**
  static bool isApi(Uri uri) {
    final String host = uri.host.toLowerCase();
    final String path = uri.path.toLowerCase();
    if (host.startsWith('api.') || host.contains('.api.')) return true;
    if (path.endsWith('.json') || path.endsWith('.xml')) return true;
    if (path.contains('/api/') ||
        path.contains('/v1/') ||
        path.contains('/v2/')) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final List<String> urls = extract(text);
    if (urls.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 6),
        ...urls.map((String u) => _card(context, u)),
      ],
    );
  }

  Widget _card(BuildContext context, String url) {
    final AppSurface s = AppSurface.of(context);

    Uri? uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      uri = null;
    }
    final bool api = uri != null && isApi(uri);

    final Color tint = api ? AppColors.warning : AppColors.accent;
    final String host = uri?.host ?? url;
    final String shownPath = uri == null
        ? ''
        : (uri.path.isEmpty ? '/' : uri.path) +
            (uri.hasQuery ? '?${uri.query}' : '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
        radius: AppRadius.field,
        onTap: onOpen == null ? null : () => onOpen!(url),
        child: Row(
          children: <Widget>[
            Container(
              width: 30,
              height: 30,
              decoration: ShapeDecoration(
                color: tint.withValues(alpha: 0.13),
                shape: const CircleBorder(),
              ),
              child: Icon(
                api ? Icons.data_object_rounded : Icons.public_rounded,
                size: 16,
                color: tint,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          host,
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
                      const SizedBox(width: 6),
                      // 明确标出是接口还是网页 —— 否则用户得自己看域名猜
                      GlassChip(
                        label: api ? 'API' : '网页',
                        dense: true,
                        color: tint,
                      ),
                    ],
                  ),
                  if (shownPath.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      shownPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.code(size: 10.5, color: s.muted),
                    ),
                  ],
                ],
              ),
            ),
            if (onOpen != null)
              Icon(Icons.chevron_right_rounded, size: 19, color: s.muted),
          ],
        ),
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});

  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _done = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _done = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _done = false);
  }

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _copy,
        child: Padding(
          // 触摸区要够大：文字只有 11px，不给内边距点不中
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                _done ? Icons.check_rounded : Icons.copy_rounded,
                size: 13,
                color: _done ? AppColors.success : s.muted,
              ),
              const SizedBox(width: 5),
              Text(
                _done ? '已复制' : '复制',
                style: AppFonts.body(
                  size: 11.5,
                  color: _done ? AppColors.success : s.muted,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
                  borderRadius: BorderRadius.circular(AppRadius.code),
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
