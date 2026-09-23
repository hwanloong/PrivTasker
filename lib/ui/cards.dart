import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../theme/app_theme.dart';
import '../theme/glass.dart';

/// AI 回复里可以插入的富卡片。
///
/// ## 协议
///
/// 用 **markdown 代码块 + 语言标签** 表达，而不是自造语法：
///
///   ```card:image
///   https://example.com/chart.png
///   ```
///
///   ```card:mermaid
///   mindmap
///     root((项目))
///       ...
///   ```
///
///   ```card:html
///   <div id="map"></div>
///   <script src="https://unpkg.com/leaflet"></script>
///   ```
///
/// **为什么用代码块**：
/// · markdown 原生结构，解析器不用动语法层
/// · **未知类型会降级成普通代码块** —— 内容不会丢，这是最关键的
/// · 模型最熟代码块，提示词里写一次例子它就会了
/// · 正文里不会碰巧撞上这个语法
///
/// ## 安全
///
/// `card:html` 会在 WebView 里执行**模型生成的 HTML/JS**。
/// 模型可能读到被污染的网页，所以这里必须当作不可信内容对待：
/// **不注入任何 JS 桥、不放开文件访问、不给硬件权限。**
/// 它就是个画布，碰不到应用的数据。
class MarkdownCards {
  const MarkdownCards._();

  /// 前缀。代码块的语言标签以它开头时，按卡片渲染。
  static const String prefix = 'card:';

  /// 内容太长就不渲染了 —— 卡片是做展示的，不是给模型倒垃圾的地方。
  /// 也顺便限制了 WebView 要跑的东西的规模。
  static const int maxChars = 20000;

  /// 能不能把这个代码块当卡片渲染。
  /// 返回 null 表示不认识 —— 那就降级成普通代码块（**内容不丢**）。
  static Widget? build({
    required String lang,
    required String content,
    required double baseSize,
  }) {
    if (!lang.startsWith(prefix)) return null;
    if (content.length > maxChars) return null;

    final String type = lang.substring(prefix.length).trim().toLowerCase();
    switch (type) {
      case 'image':
        return CardImage(url: content.trim());
      case 'mermaid':
        return CardWebView(
          title: '图表',
          html: _mermaidTemplate(content),
        );
      case 'html':
        return CardWebView(title: '嵌入内容', html: _normalizeHtml(content));
      default:
        // 不认识的卡片类型 → 降级为代码块，内容不丢。
        // 这样以后加新类型时，旧版应用也不会把它显示成空白。
        return null;
    }
  }

  /// 给模型生成的 HTML 补上移动端必需的东西。
  ///
  /// **这是"只显示半边"的根因**：模型写的 HTML 一般没有 viewport meta 标签，
  /// 于是手机的 WebView 按桌面宽度（约 980px）布局，
  /// 在几百像素宽的卡片里就只露出左边一块。
  ///
  /// 顺手还补了一个重置样式：默认 body 有 8px margin，
  /// 会让内容整体偏移、右边多出一条。
  static String _normalizeHtml(String html) {
    final StringBuffer sb = StringBuffer();

    // 有 <head> 就插进去，没有就在开头补一个
    final bool hasViewport = RegExp(
      r'<meta[^>]+name\s*=\s*["' "'" r']viewport',
      caseSensitive: false,
    ).hasMatch(html);

    const String viewportTag =
        '<meta name="viewport" content="width=device-width, '
        'initial-scale=1, maximum-scale=5">';

    const String resetStyle = '<style>'
        'html,body{margin:0;padding:0;overflow-x:hidden;}'
        'body{background:transparent;}'
        'img,canvas,svg,table{max-width:100%;}'
        '</style>';

    if (RegExp(r'<head[^>]*>', caseSensitive: false).hasMatch(html)) {
      // 有 head：在它后面插入
      sb.write(html.replaceFirstMapped(
        RegExp(r'<head[^>]*>', caseSensitive: false),
        (Match m) =>
            '${m.group(0)}${hasViewport ? '' : viewportTag}$resetStyle',
      ));
    } else {
      // 没有 head（模型常直接给片段）：自己包一层
      sb.write('<!DOCTYPE html><html><head><meta charset="utf-8">');
      if (!hasViewport) sb.write(viewportTag);
      sb.write(resetStyle);
      sb.write('</head><body>');
      sb.write(html);
      sb.write('</body></html>');
    }

    return sb.toString();
  }

  /// 把 mermaid 源码包成一个能自渲染的页面。
  ///
  /// mermaid 从 CDN 加载。**国内 CDN 可能不通** —— 页面里做了失败提示，
  /// 而不是留一片空白（空白最糟：用户不知道是加载失败还是没内容）。
  static String _mermaidTemplate(String source) {
    // 转义 </script> 之类，避免源码里的字符串提前闭合标签
    final String safe = source
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');

    return '''
<!DOCTYPE html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  body{margin:0;padding:12px;background:transparent;
       font-family:-apple-system,sans-serif}
  #out{display:flex;justify-content:center}
  #err{color:#c0392b;font-size:13px;line-height:1.6;padding:8px}
</style></head><body>
<div id="out"><pre class="mermaid">$safe</pre></div>
<div id="err"></div>
<script type="module">
  const err = document.getElementById('err');
  const src = 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
  // 双 CDN 兜底：jsdelivr 在国内时通时不通，unpkg 作为备选
  const fallback = 'https://unpkg.com/mermaid@11/dist/mermaid.esm.min.mjs';
  async function load(){
    for (const url of [src, fallback]) {
      try {
        const m = await import(url);
        m.default.initialize({startOnLoad:true, theme:'neutral',
                              securityLevel:'strict'});
        await m.default.run();
        return;
      } catch(e) { /* 试下一个 */ }
    }
    err.textContent = '图表库加载失败（CDN 不可达）。原始内容已在下方代码块中保留。';
  }
  load();
</script>
</body></html>''';
  }
}

/// `card:image` —— 直接显示图片。
///
/// AI 调外部渲染 API（比如把公式/图表渲染成 PNG 的服务）拿到链接后，
/// 用这个卡片插进回复里。
class CardImage extends StatelessWidget {
  const CardImage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);
    final String host = Uri.tryParse(url)?.host ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SurfaceCard(
        padding: const EdgeInsets.all(8),
        radius: AppRadius.field,
        // 点图片 → 全屏，用 InteractiveViewer 双指缩放。
        // 缩略图那个尺寸看不出图上写了什么。
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext _) => CardFullscreenPage(
              title: host.isEmpty ? '图片' : host,
              imageUrl: url,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.code),
              child: Image.network(
                url,
                fit: BoxFit.contain,
                // 加载/失败都要有反馈：这是网络图片，失败很常见，
                // 留一片空白用户会以为是应用坏了
                loadingBuilder: (BuildContext _, Widget child,
                    ImageChunkEvent? p) {
                  if (p == null) return child;
                  return SizedBox(
                    height: 120,
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accent,
                          value: p.expectedTotalBytes == null
                              ? null
                              : p.cumulativeBytesLoaded /
                                  p.expectedTotalBytes!,
                        ),
                      ),
                    ),
                  );
                },
                errorBuilder: (BuildContext _, Object e, StackTrace? _) =>
                    Container(
                  height: 110,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.broken_image_outlined,
                          size: 26, color: s.muted),
                      const SizedBox(height: 6),
                      Text(
                        '图片加载失败',
                        style: AppFonts.body(size: 12.5, color: s.muted),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        host,
                        style: AppFonts.code(size: 10.5, color: s.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (host.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 2),
                child: Text(
                  host,
                  style: AppFonts.code(size: 10.5, color: s.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 全屏查看卡片内容。
///
/// 思维导图、地图这类内容，卡片里那 260px 高度是**看不了细节的** ——
/// 必须给一个能放大、能拖动的全屏视图，否则卡片只是"知道有这么个东西"。
class CardFullscreenPage extends StatelessWidget {
  const CardFullscreenPage({
    super.key,
    required this.title,
    this.html,
    this.imageUrl,
  });

  final String title;

  /// 二者其一必填
  final String? html;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);
    final double top = MediaQuery.of(context).padding.top;
    final double bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: s.isDark ? AppColors.darkBg : AppColors.lightBg,
      body: Column(
        children: <Widget>[
          GlassBar(
            hairlineBottom: true,
            padding: EdgeInsets.fromLTRB(8, top + 6, 14, 10),
            child: Row(
              children: <Widget>[
                GlassIconButton(
                  icon: Icons.close_rounded,
                  tooltip: '关闭',
                  size: 38,
                  iconSize: 19,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: AppFonts.body(
                      size: 16,
                      weight: FontWeight.w700,
                      color: s.text,
                      height: 1.2,
                    ),
                  ),
                ),
                Text(
                  '双指缩放',
                  style: AppFonts.body(size: 11.5, color: s.muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: imageUrl != null
                  ? _imageView()
                  : _webView(),
            ),
          ),
        ],
      ),
    );
  }

  /// 图片：用 InteractiveViewer 实现双指缩放 + 拖动
  Widget _imageView() {
    return InteractiveViewer(
      minScale: 1.0,
      maxScale: 6.0,
      // 允许拖到边界外一点，缩放大图时手感更好
      boundaryMargin: const EdgeInsets.all(40),
      child: Center(
        child: Image.network(
          imageUrl!,
          fit: BoxFit.contain,
          errorBuilder: (BuildContext _, Object e, StackTrace? _) => Center(
            child: Text(
              '图片加载失败',
              style: AppFonts.body(size: 13),
            ),
          ),
        ),
      ),
    );
  }

  /// HTML：WebView 自带缩放。**这里开着 allowFileAccess 之外的一切照旧**，
  /// 但依然不注入任何 JS 桥 —— 全屏不等于可以碰应用数据。
  Widget _webView() {
    return InAppWebView(
      initialData: InAppWebViewInitialData(
        data: html!,
        mimeType: 'text/html',
        encoding: 'utf-8',
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        allowFileAccess: false,
        allowContentAccess: false,
        geolocationEnabled: false,
        transparentBackground: true,
        cacheEnabled: true,
        clearCache: false,
        // ---- 缩放相关 ----
        supportZoom: true,
        builtInZoomControls: true,
        // 隐藏 WebView 自带的 +/- 按钮：又丑又占地方，
        // 双指缩放已经够了
        displayZoomControls: false,
        useWideViewPort: false,
        loadWithOverviewMode: true,
        // **不要设 initialScale**。设了它（比如 100）就固定了缩放比例，
        // 页面会按桌面宽度渲染，在手机屏上只露出左边一半 —— 就是"只显示半边"。
        // 交给 viewport meta 自己决定就好。
      ),
    );
  }
}

/// `card:html` / `card:mermaid` —— 在沙箱 WebView 里渲染。
///
/// **高度固定**：WebView 是平台视图，没法自己量内容高度。
/// 所以给一个固定高度 + 可展开，而不是让它撑开 —— 撑开会把列表布局搞乱。
class CardWebView extends StatefulWidget {
  const CardWebView({
    super.key,
    required this.title,
    required this.html,
    this.height = 260,
  });

  final String title;
  final String html;
  final double height;

  @override
  State<CardWebView> createState() => _CardWebViewState();
}

class _CardWebViewState extends State<CardWebView> {
  // 展开状态已由全屏页承担，这里不再需要
  bool _failed = false;

  /// 重建计数。**改它的值会让 WebView 被销毁重建** ——
  /// 这是唯一可靠的"重新加载"手段（见 _reload 的注释）。
  int _buildId = 0;

  /// 重新渲染卡片。
  ///
  /// **为什么不能只调 controller.reload()**：
  /// 内容是用 `initialData` 喂进去的，页面并没有一个"地址"可以重载；
  /// 而且失败往往发生在**创建阶段**（平台视图没起来、CDN 没加载到），
  /// 那种情况 reload 也救不回来。
  ///
  /// 所以改用换 Key 强制重建 —— Flutter 会销毁旧的 State 和它持有的
  /// WebView，然后完整地重新走一遍创建流程。
  /// 这在"卡住了想再试一次"时是真正有效的。
  void _reload() {
    setState(() {
      _buildId++;
      _failed = false;
    });
  }

  void _openFullscreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => CardFullscreenPage(
          title: widget.title,
          html: widget.html,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);
    final double h = widget.height;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      // ⚠️ **不能用 SurfaceCard**。
      //
      // SurfaceCard 的内部实现为了做圆角**总会对子内容 ClipPath**，
      // 而 Android 上被裁剪的**平台视图（WebView）会渲染成空白** ——
      // 平台视图是单独的合成层，参与不了父级的裁剪。
      // 表现就是"内联卡片什么都不显示，但全屏（没有裁剪）正常"。
      //
      // 所以这里用普通 Container：BoxDecoration 只画背景和描边，
      // **不裁剪子级**，WebView 才能正常渲染。
      // 代价是 WebView 自己是直角 —— 用内边距让它看起来是有意为之。
      child: Container(
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: BorderRadius.circular(AppRadius.field),
          border: Border.all(color: s.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // ---- 标题栏 ----
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 6, 6),
              child: Row(
                children: <Widget>[
                  Icon(Icons.widgets_outlined,
                      size: 14, color: AppColors.accent),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: AppFonts.body(
                        size: 12,
                        weight: FontWeight.w600,
                        color: s.muted,
                        height: 1.2,
                      ),
                    ),
                  ),
                  // 刷新：强制重建 WebView，用于"卡住了再试一次"。
                  // 不用重启应用 —— 那正是之前卡片不显示时用户被迫做的事。
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _reload,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.refresh_rounded,
                        size: 15,
                        color: s.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _openFullscreen,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.open_in_full_rounded,
                        size: 15,
                        color: s.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ---- 内容 ----
            // 点卡片任意位置 → 全屏查看。
            // 卡片里那点高度看不了细节，全屏才是真正"能看"的地方。
            //
            // ⚠️ **这里绝对不能套 ClipRRect**（之前套了，正是这个原因导致空白）。
            // 裁剪平台视图会让它在 Android 上渲染不出来。
            // 所以用 Padding 做内缩，让直角看起来是有意的留白。
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openFullscreen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                child: SizedBox(
                  height: h,
                  width: double.infinity,
                  child: _failed
                      ? _fallback(s)
                      : InAppWebView(
                          // Key 变化 → 整个 WebView 被销毁重建。
                          // 这是"重新渲染"真正生效的关键：initialData 只在
                          // 创建时读一次，不换 Key 的话传新数据也没用。
                          key: ValueKey<int>(_buildId),
                          // 内容直接给 HTML 字符串，不走网络加载文档本身
                          initialData: InAppWebViewInitialData(
                            data: widget.html,
                            mimeType: 'text/html',
                            encoding: 'utf-8',
                          ),
                          initialSettings: InAppWebViewSettings(
                            // ---- 沙箱：能画东西，但碰不到应用 ----
                            // 不开 JS 桥（不调 addJavaScriptHandler）——
                            // 这是最关键的一条：卡片无法回调到 Dart 侧。
                            javaScriptEnabled: true,
                            // 不放开文件访问：模型生成的 HTML 不该读到本机文件
                            allowFileAccess: false,
                            allowContentAccess: false,
                            // 不给硬件权限
                            geolocationEnabled: false,
                            // 透明背景，跟主题融为一体
                            transparentBackground: true,
                            // 地图/图表要加载 CDN，所以网络必须开 ——
                            // 这是沙箱的唯一缺口，用"不给桥"来补偿
                            cacheEnabled: true,
                            clearCache: false,
                            disableContextMenu: true,
                            // 卡片里也能双指缩放（虽然空间小，但总比没有好）
                            supportZoom: true,
                            builtInZoomControls: true,
                            displayZoomControls: false,
                            // 和全屏页保持一致 —— 这两个决定了页面按移动端
                            // 宽度渲染还是按桌面宽度渲染（"只显示半边"的根源）
                            useWideViewPort: false,
                            loadWithOverviewMode: true,
                          ),
                          onReceivedError: (InAppWebViewController _,
                              WebResourceRequest req, WebResourceError err) {
                            // 只有主文档失败才算失败；CDN 子资源失败由页面自己提示
                            if (req.isForMainFrame == true && mounted) {
                              setState(() => _failed = true);
                            }
                          },
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// WebView 起不来时的兜底：**至少让用户看到内容还在**，
  /// 而不是一片空白。
  Widget _fallback(AppSurface s) {
    return Container(
      color: s.codeBg,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.layers_clear_outlined, size: 24, color: s.muted),
          const SizedBox(height: 8),
          Text(
            '卡片渲染失败',
            style: AppFonts.body(
              size: 13,
              weight: FontWeight.w600,
              color: s.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '内容没有被丢弃 —— 切到「原文」可以看到它',
            textAlign: TextAlign.center,
            style: AppFonts.body(size: 11.5, color: s.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}
