import 'dart:convert';

import '../core/models.dart';
import 'tool.dart';
import 'webview_loader.dart';

/// 搜索引擎定义
class SearchEngine {
  const SearchEngine(this.id, this.label, this.urlTemplate);

  final String id;
  final String label;

  /// `%s` 会被替换成 URL 编码后的关键词
  final String urlTemplate;

  static const List<SearchEngine> all = <SearchEngine>[
    SearchEngine('bing', 'Bing', 'https://www.bing.com/search?q=%s'),
    SearchEngine('baidu', '百度', 'https://www.baidu.com/s?wd=%s'),
    SearchEngine('duckduckgo', 'DuckDuckGo', 'https://duckduckgo.com/?q=%s'),
    SearchEngine('google', 'Google', 'https://www.google.com/search?q=%s'),
  ];

  static SearchEngine byId(String id) {
    for (final SearchEngine e in all) {
      if (e.id == id) return e;
    }
    return all.first;
  }
}

/// 一次抓取的完整结果，含诊断信息
class _Extract {
  const _Extract({
    required this.items,
    required this.title,
    required this.url,
    required this.textLen,
    required this.counts,
    required this.hints,
    required this.sample,
  });

  final List<Map<String, dynamic>> items;
  final String title;
  final String url;
  final int textLen;
  final Map<String, int> counts;
  final List<String> hints;

  /// 页面可见文本的开头，用于判断到底加载出了什么
  final String sample;

  /// 把「为什么没取到结果」讲清楚，而不是甩一句猜测
  String diagnose() {
    final StringBuffer sb = StringBuffer();
    if (url.isNotEmpty) sb.writeln('  最终地址：$url');
    if (title.isNotEmpty) sb.writeln('  页面标题：$title');
    sb.writeln('  可见文本长度：$textLen');

    if (counts.isNotEmpty) {
      final String c = counts.entries
          .map((MapEntry<String, int> e) => '${e.key}=${e.value}')
          .join(', ');
      sb.writeln('  选择器命中：$c');
    }

    if (hints.contains('captcha')) {
      sb.writeln('  疑似：触发了人机验证');
    } else if (hints.contains('empty')) {
      sb.writeln('  疑似：页面没渲染出内容（可能被拦截或加载未完成）');
    } else if (hints.contains('consent')) {
      sb.writeln('  疑似：被 Cookie/同意页挡住');
    } else if (counts.isNotEmpty && counts.values.every((int v) => v == 0)) {
      sb.writeln('  疑似：页面结构变了，所有选择器都没命中');
    } else {
      sb.writeln('  疑似：命中了元素但没解析出有效链接');
    }

    if (sample.trim().isNotEmpty) {
      final String s =
          sample.length > 220 ? '${sample.substring(0, 220)}…' : sample;
      sb.writeln('  页面开头：$s');
    }
    return sb.toString().trimRight();
  }
}

/// 通过**内置浏览器（WebView）**抓取网页或搜索结果。
///
/// 为什么不用普通 HTTP 请求：服务端抓取很容易被反爬识别——
/// 没有 JS 执行、没有 Cookie、没有真实浏览器指纹，DuckDuckGo 会直接返回
/// anomaly 拦截页（实测 HTTP 202 + 零结果）。而 WebView 是真浏览器环境：
/// 真实 UA、执行 JS、带 Cookie、走手机的家庭 IP。
///
/// 两个关键设计：
///  1. **轮询而非等固定时间**：见 [WebViewLoader.load]。
///  2. **失败要有诊断**：一个引擎没结果时自动换下一个，并返回每个引擎的
///     真实情况（最终地址、页面标题、选择器命中数、页面文本开头）。
///     只回一句「关键词太偏」等于什么都没说。
class BrowserTool extends AgentTool {
  const BrowserTool();

  @override
  String get name => 'browser';

  @override
  String get title => '浏览器';

  @override
  String get description =>
      '用内置浏览器打开网页并读取内容。因为是真实浏览器环境，'
      '能拿到需要 JS 渲染的页面，也不容易被反爬拦截。'
      'action：search（搜索，会自动在多个引擎间重试）、'
      'open（打开指定网址并提取正文）。'
      '抓取比普通请求慢，需要等待页面渲染。';

  @override
  Map<String, dynamic> get parameters => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'action': <String, dynamic>{
            'type': 'string',
            'enum': <String>['search', 'open'],
          },
          'query': <String, dynamic>{
            'type': 'string',
            'description': 'search 的关键词',
          },
          'url': <String, dynamic>{
            'type': 'string',
            'description': 'open 的完整网址',
          },
          'engine': <String, dynamic>{
            'type': 'string',
            'enum': <String>['bing', 'baidu', 'duckduckgo', 'google'],
            'description': '优先使用哪个引擎，默认取设置里的值',
          },
          'limit': <String, dynamic>{
            'type': 'integer',
            'description': '返回条数，默认 6',
          },
        },
        'required': <String>['action'],
      };

  @override
  RiskAssessment riskFor(Map<String, dynamic> args) => RiskAssessment.safe;

  @override
  String summarize(Map<String, dynamic> args) {
    if (args.str('action') == 'search') {
      return '搜索 ${args.str('query')}';
    }
    return '打开 ${args.str('url')}';
  }

  @override
  Future<String> run(ToolContext ctx, Map<String, dynamic> args) async {
    final String action = args.str('action');

    if (action == 'open') {
      final String url = args.str('url').trim();
      if (url.isEmpty) return '错误：缺少 url';
      final Uri? uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) return '错误：url 不合法 —— $url';

      final String? raw = await WebViewLoader.load(
        url: url,
        js: WebViewLoader.extractTextJs,
        isDone: (String s) =>
            WebViewLoader.unwrapJsString(s).trim().length > 200,
        attempts: 5,
      );
      if (raw == null) return '打开 $url 超时或失败。';

      final String text = WebViewLoader.unwrapJsString(raw);
      if (text.trim().isEmpty) {
        return '打开 $url 成功，但页面没有可读文本（可能是纯图片页或需要登录）。';
      }
      return 'URL: $url\n\n${clampOutput(text, max: 9000)}';
    }

    if (action != 'search') return '错误：未知 action「$action」';

    final String query = args.str('query').trim();
    if (query.isEmpty) return '错误：缺少 query';

    final String preferred = args.str('engine').trim().isNotEmpty
        ? args.str('engine').trim()
        : (ctx.searchEngine.trim().isEmpty ? 'bing' : ctx.searchEngine.trim());

    // 引擎顺序：**百度优先**，然后才是用户指定的那个，最后是其余。
    //
    // 为什么把百度提到最前：国内网络下 Bing 和 Google 要么连不上，
    // 要么对老旧的系统 WebView 返回「请升级浏览器」页面 —— 抓不到结果，
    // 却要**等满 15 秒超时**才换下一个。而每换一个引擎都要重建一次
    // Chromium 实例（又是十几秒）。
    //
    // 结果就是：每次搜索先白等二十多秒才轮到真正能用的那个。
    // 百度是国内站点，不受墙影响，对 WebView 版本也最宽容 ——
    // 它才是这台机器上最可能立刻成功的一条。
    final SearchEngine primary = SearchEngine.byId(preferred);
    final SearchEngine first = SearchEngine.byId('baidu');
    final List<SearchEngine> order = <SearchEngine>[
      if (first.id != primary.id) first,
      primary,
      ...SearchEngine.all.where(
        (SearchEngine e) => e.id != primary.id && e.id != first.id,
      ),
    ];

    final int limit = args.intVal('limit', fallback: 6).clamp(1, 15);
    final List<String> reports = <String>[];
    final String encoded = Uri.encodeComponent(query);

    // 总时间预算。
    // 不加这个的话，4 个引擎各自超时叠加起来能跑 2 分多钟，
    // 用户看到的就是「卡住了」——明明还活着，但没有任何进展提示。
    //
    // 收到 30 秒：这条通道是**最后的兜底**，走到这里说明前面几层都失败了，
    // 与其让用户干等，不如早点给出一份带诊断的失败说明。
    const int budgetSeconds = 30;
    final DateTime deadline =
        DateTime.now().add(const Duration(seconds: budgetSeconds));

    for (final SearchEngine engine in order) {
      if (DateTime.now().isAfter(deadline)) {
        reports.add('【${engine.label}】已超出总时间预算（$budgetSeconds 秒），跳过');
        continue;
      }

      final String url = engine.urlTemplate.replaceFirst('%s', encoded);

      final String? raw = await WebViewLoader.load(
        url: url,
        js: _kSearchJs,
        isDone: _hasItems,
        // 自适应轮询下 5 次约 3.2 秒，够用；超时压到 15 秒，
        // 让「跑不通就快点报错」优先于「死等到最后一刻」。
        attempts: 5,
        timeout: const Duration(seconds: 15),
      );

      if (raw == null) {
        reports.add('【${engine.label}】页面加载超时或失败');
        continue;
      }

      final _Extract ex = _parse(raw);
      if (ex.items.isNotEmpty) {
        return _formatSearch(ex, engine, limit);
      }
      reports.add('【${engine.label}】没取到结果\n${ex.diagnose()}');
    }

    final String names =
        order.map((SearchEngine e) => e.label).join('、');
    return '依次试了 ${order.length} 个搜索引擎（$names），都没取到结果。'
        '以下是每个引擎的真实情况：\n\n'
        '${reports.join('\n\n')}\n\n'
        '如果每个引擎的「可见文本长度」都很小（几百以内），说明页面根本没加载出来，'
        '多半是网络问题；如果文本很长但选择器全为 0，是页面结构变了。';
  }

  // ------------------------------------------------------------ 解析与格式化

  static bool _hasItems(String raw) {
    try {
      final Map<String, dynamic> m = _asMap(raw);
      final List<dynamic> items =
          (m['items'] as List<dynamic>?) ?? <dynamic>[];
      return items.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Map<String, dynamic> _asMap(String raw) {
    final String s = WebViewLoader.unwrapJsString(raw);
    final dynamic j = jsonDecode(s);
    if (j is Map) return Map<String, dynamic>.from(j);
    if (j is List) return <String, dynamic>{'items': j};
    return <String, dynamic>{};
  }

  _Extract _parse(String raw) {
    Map<String, dynamic> m;
    try {
      m = _asMap(raw);
    } catch (_) {
      return _Extract(
        items: <Map<String, dynamic>>[],
        title: '',
        url: '',
        textLen: 0,
        counts: <String, int>{},
        hints: <String>['parse-error'],
        sample: raw.length > 300 ? raw.substring(0, 300) : raw,
      );
    }

    final List<Map<String, dynamic>> items =
        ((m['items'] as List<dynamic>?) ?? <dynamic>[])
            .whereType<Map>()
            .map((Map e) => Map<String, dynamic>.from(e))
            .toList();

    return _Extract(
      items: items,
      title: m['title']?.toString() ?? '',
      url: m['url']?.toString() ?? '',
      textLen: (m['textLen'] as num?)?.toInt() ?? 0,
      counts: ((m['counts'] as Map?) ?? <String, dynamic>{}).map(
        (dynamic k, dynamic v) =>
            MapEntry<String, int>(k.toString(), (v as num?)?.toInt() ?? 0),
      ),
      hints: ((m['hints'] as List<dynamic>?) ?? <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList(),
      sample: m['sample']?.toString() ?? '',
    );
  }

  String _formatSearch(_Extract ex, SearchEngine engine, int limit) {
    final StringBuffer sb = StringBuffer();
    sb.writeln('（来源：${engine.label} · 内置浏览器抓取）\n');
    final int n = ex.items.length < limit ? ex.items.length : limit;
    for (int i = 0; i < n; i++) {
      final Map<String, dynamic> m = ex.items[i];
      final String title = (m['t'] ?? '').toString().trim();
      final String url = (m['u'] ?? '').toString().trim();
      String snippet = (m['s'] ?? '').toString().trim();
      if (snippet.length > 300) snippet = '${snippet.substring(0, 300)}…';

      sb.writeln('[${i + 1}] $title');
      sb.writeln('    $url');
      if (snippet.isNotEmpty) sb.writeln('    $snippet');
      sb.writeln();
    }
    return clampOutput(sb.toString());
  }

  // ------------------------------------------------------------ 注入的脚本

  /// 依次尝试各引擎的结果选择器，最后用通用兜底，
  /// 并额外返回诊断信息（标题、地址、可见文本长度、各选择器命中数、页面开头）。
  static const String _kSearchJs = r'''
(function () {
  function clean(s) { return (s || '').replace(/\s+/g, ' ').trim(); }
  var out = [];
  function push(title, url, snippet) {
    title = clean(title); url = (url || '').trim(); snippet = clean(snippet);
    if (!title || !url || url.indexOf('http') !== 0) return;
    for (var i = 0; i < out.length; i++) { if (out[i].u === url) return; }
    out.push({ t: title, u: url, s: snippet });
  }

  var counts = {};

  counts['bing'] = document.querySelectorAll('#b_results > li.b_algo').length;
  document.querySelectorAll('#b_results > li.b_algo').forEach(function (li) {
    var a = li.querySelector('h2 a');
    var p = li.querySelector('.b_caption p') || li.querySelector('p');
    if (a) push(a.innerText, a.href, p ? p.innerText : '');
  });

  counts['baidu'] = document.querySelectorAll('div.result, div.c-container').length;
  if (!out.length) {
    document.querySelectorAll('div.result, div.c-container').forEach(function (d) {
      var a = d.querySelector('h3 a') || d.querySelector('a');
      if (a) push(a.innerText, a.href, d.innerText);
    });
  }

  counts['ddg'] = document.querySelectorAll('article[data-testid="result"], div.result').length;
  if (!out.length) {
    document.querySelectorAll('article[data-testid="result"], div.result').forEach(function (d) {
      var a = d.querySelector('a[data-testid="result-title-a"], h2 a, a.result__a');
      var p = d.querySelector('[data-result="snippet"], .result__snippet');
      if (a) push(a.innerText, a.href, p ? p.innerText : '');
    });
  }

  counts['google'] = document.querySelectorAll('div.g, div[data-hveid]').length;
  if (!out.length) {
    document.querySelectorAll('div.g, div[data-hveid]').forEach(function (d) {
      var h = d.querySelector('h3');
      var a = d.querySelector('a');
      if (h && a) push(h.innerText, a.href, d.innerText);
    });
  }

  counts['generic'] = document.querySelectorAll('h2 a, h3 a').length;
  if (!out.length) {
    document.querySelectorAll('h2 a, h3 a').forEach(function (a) {
      var box = a.closest('div, li, section');
      push(a.innerText, a.href, box ? box.innerText : '');
    });
  }

  var bodyText = clean(document.body ? document.body.innerText : '');
  var low = bodyText.toLowerCase();
  var hints = [];
  if (/captcha|unusual traffic|are you a robot|人机验证|请输入验证码|安全验证/.test(low)) hints.push('captcha');
  if (bodyText.length < 200) hints.push('empty');
  if (!out.length && /cookie|consent|同意|接受全部/.test(low)) hints.push('consent');

  return JSON.stringify({
    items: out.slice(0, 20),
    title: document.title || '',
    url: location.href,
    textLen: bodyText.length,
    counts: counts,
    hints: hints,
    sample: bodyText.slice(0, 300)
  });
})()
''';
}
