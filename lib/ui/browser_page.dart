import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../tools/webview_loader.dart';

/// 应用内浏览器。
///
/// 用途：从聊天里的网页卡片点开、预览 AI 给出的链接、
/// 或者需要登录/交互才能看到内容的页面（抓取拿不到时用它人工看一眼）。
///
/// 刻意做成「真实的浏览器」而不是只读渲染：
/// 带地址栏、前进后退、刷新、外部打开。很多页面需要滚动和点击才有内容。
class BrowserPage extends StatefulWidget {
  const BrowserPage({
    super.key,
    required this.initialUrl,
    this.title,
  });

  final String initialUrl;
  final String? title;

  static Future<void> open(
    BuildContext context, {
    required String url,
    String? title,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) =>
            BrowserPage(initialUrl: url, title: title),
      ),
    );
  }

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  InAppWebViewController? _controller;
  late final TextEditingController _urlField;

  double _progress = 0;
  bool _loading = true;
  String _currentUrl = '';
  String _pageTitle = '';
  bool _canBack = false;
  bool _canForward = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
    _pageTitle = widget.title ?? '';
    _urlField = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _urlField.dispose();
    super.dispose();
  }

  void _navigate(String raw) {
    String u = raw.trim();
    if (u.isEmpty) return;
    // 容忍直接输入域名
    if (!u.contains('://')) u = 'https://$u';
    final Uri? uri = Uri.tryParse(u);
    if (uri == null || !uri.hasScheme) return;
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(u)));
  }

  Future<void> _syncNavState(InAppWebViewController c) async {
    final bool back = await c.canGoBack();
    final bool fwd = await c.canGoForward();
    if (mounted) {
      setState(() {
        _canBack = back;
        _canForward = fwd;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);
    final double topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor:
          s == AppSurface.dark ? AppColors.darkBg : AppColors.lightBg,
      body: Column(
        children: <Widget>[
          GlassBar(
            hairlineBottom: true,
            padding: EdgeInsets.fromLTRB(10, topInset + 6, 12, 8),
            child: Row(
              children: <Widget>[
                GlassIconButton(
                  icon: Icons.close_rounded,
                  tooltip: '关闭',
                  size: 34,
                  iconSize: 18,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: s.surface,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: s.border, width: 0.9),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: TextField(
                      controller: _urlField,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      onSubmitted: _navigate,
                      style: AppFonts.body(size: 13.5, color: s.text),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: '输入网址',
                        hintStyle: AppFonts.body(size: 13.5, color: s.muted),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                GlassIconButton(
                  icon: Icons.open_in_new_rounded,
                  tooltip: '用系统浏览器打开',
                  size: 34,
                  iconSize: 17,
                  onTap: () async {
                    final Uri? uri = Uri.tryParse(_currentUrl);
                    if (uri == null) return;
                    try {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    } catch (_) {
                      // 忽略
                    }
                  },
                ),
              ],
            ),
          ),
          if (_loading && _progress < 1)
            LinearProgressIndicator(
              value: _progress == 0 ? null : _progress,
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: AppColors.accent,
            ),
          Expanded(
            child: Stack(
              children: <Widget>[
                InAppWebView(
                  initialUrlRequest:
                      URLRequest(url: WebUri(widget.initialUrl)),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    domStorageEnabled: true,
                    mediaPlaybackRequiresUserGesture: true,
                    useShouldInterceptRequest: false,
                    userAgent: WebViewLoader.mobileUserAgent,
                  ),
                  onWebViewCreated: (InAppWebViewController c) {
                    _controller = c;
                  },
                  onLoadStart: (InAppWebViewController c, WebUri? uri) {
                    if (!mounted) return;
                    setState(() {
                      _loading = true;
                      _error = null;
                      if (uri != null) {
                        _currentUrl = uri.toString();
                        _urlField.text = _currentUrl;
                      }
                    });
                  },
                  onLoadStop: (InAppWebViewController c, WebUri? uri) async {
                    if (!mounted) return;
                    setState(() {
                      _loading = false;
                      if (uri != null) {
                        _currentUrl = uri.toString();
                        _urlField.text = _currentUrl;
                      }
                    });
                    final String? t = await c.getTitle();
                    if (mounted && t != null && t.isNotEmpty) {
                      setState(() => _pageTitle = t);
                    }
                    await _syncNavState(c);
                  },
                  onProgressChanged: (InAppWebViewController c, int p) {
                    if (!mounted) return;
                    setState(() => _progress = p / 100);
                  },
                  onReceivedError: (
                    InAppWebViewController c,
                    WebResourceRequest req,
                    WebResourceError err,
                  ) {
                    // 只有主文档失败才提示；子资源失败很常见，不用打扰用户
                    if (req.isForMainFrame == true && mounted) {
                      setState(() {
                        _loading = false;
                        _error = err.description;
                      });
                    }
                  },
                ),
                if (_error != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: SurfaceCard(
                      color: AppColors.danger.withValues(alpha: 0.10),
                      borderColor:
                          AppColors.danger.withValues(alpha: 0.30),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.error_outline_rounded,
                              size: 16, color: AppColors.danger),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '加载失败：$_error',
                              style: AppFonts.body(
                                  size: 12.5,
                                  color: AppColors.danger,
                                  height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          GlassBar(
            hairlineTop: true,
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              8 + MediaQuery.of(context).padding.bottom,
            ),
            child: Row(
              children: <Widget>[
                GlassIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: '后退',
                  size: 36,
                  iconSize: 18,
                  onTap: _canBack
                      ? () async {
                          await _controller?.goBack();
                          if (_controller != null) {
                            await _syncNavState(_controller!);
                          }
                        }
                      : null,
                ),
                const SizedBox(width: 8),
                GlassIconButton(
                  icon: Icons.arrow_forward_rounded,
                  tooltip: '前进',
                  size: 36,
                  iconSize: 18,
                  onTap: _canForward
                      ? () async {
                          await _controller?.goForward();
                          if (_controller != null) {
                            await _syncNavState(_controller!);
                          }
                        }
                      : null,
                ),
                const SizedBox(width: 8),
                GlassIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: '刷新',
                  size: 36,
                  iconSize: 18,
                  onTap: () => _controller?.reload(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _pageTitle.isEmpty ? _currentUrl : _pageTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.body(
                        size: 12, color: s.muted, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
