import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ids.dart';
import 'models.dart';

/// 全局设置，用 SharedPreferences 持久化。
class Settings extends ChangeNotifier {
  Settings._(this._prefs);

  final SharedPreferences _prefs;

  static Future<Settings> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final Settings s = Settings._(p);
    s._read();
    return s;
  }

  // ------------------------------------------------------------ 对话模型

  String apiKey = '';
  String baseUrl = 'https://api.deepseek.com';

  /// 当前 DeepSeek 官方模型：
  ///  · deepseek-flash    —— V4.1-Flash，1M 上下文，**支持图像理解**
  ///  · deepseek-v4-pro   —— V4-Pro，不支持图像理解
  /// 旧名 deepseek-chat / deepseek-reasoner 已不在模型表中。
  String model = 'deepseek-flash';

  /// 是否开启思考模式。DeepSeek 默认开启。
  bool thinkingEnabled = true;

  /// 思考强度：low / high / max。
  /// 官方映射表：minimal、low → low；medium、high、xhigh → high；max、ultra → max。
  String reasoningEffort = 'high';

  double temperature = 0.7;

  /// 单轮对话里最多允许多少次工具调用往返，防止模型陷入死循环
  int maxToolRounds = 8;

  /// 可选模型清单（仍可手动填其它名字）
  static const List<(String, String)> modelPresets = <(String, String)>[
    ('deepseek-flash', 'V4.1 Flash · 支持图像理解 · 1M 上下文'),
    ('deepseek-v4-pro', 'V4 Pro · 不支持图像理解'),
  ];

  static const List<(String, String)> effortPresets = <(String, String)>[
    ('low', '低 · 快，适合简单操作'),
    ('high', '高 · 默认，平衡'),
    ('max', '最大 · 最慢最贵，适合复杂推理'),
  ];

  // ------------------------------------------------------------ 联网

  /// Tavily 搜索 key。留空时走 DuckDuckGo 兜底。
  String searchApiKey = '';

  /// 内置浏览器抓取搜索时用的搜索引擎。
  /// 走 WebView 而不是 HTTP 请求，所以不受反爬拦截影响。
  String searchEngine = 'bing';

  /// 联网搜索走哪条通道：
  ///  auto     —— 依次尝试 DeepSeek 服务端 → Tavily → 内置浏览器抓取
  ///  deepseek —— 只用 DeepSeek Responses API 的服务端 web_search
  ///  browser  —— 只用内置浏览器抓取
  String webSearchMode = 'auto';

  /// 自建搜索服务的地址（agent-web-search 这类）。
  ///
  /// 它是**独立部署的服务**（Docker + SearXNG），不在手机上跑，
  /// 所以这里只存一个 HTTP 地址。留空则跳过这一层。
  /// 价值在于它替我们做完了「抓取 → 正文提取 → 去噪 → 分块 → 向量化 →
  /// 相关度排序」整条链，拿回来就是能直接读的资料，还自带提示注入清洗。
  String selfHostedSearchUrl = '';

  /// 联网方式。
  ///
  /// 自建搜索服务与 DeepSeek 服务端搜索已移除：
  /// · 自建服务要自己部署 Docker + SearXNG，门槛太高，而且跑在手机上
  ///   仍然受手机网络限制（墙的问题没解决，只是换了台机器）；
  /// · DeepSeek 的 `web_search` 已被官方关闭 —— 响应里不再出现
  ///   `web_search_call`，实测确认，官方文档也一直标着「忽略」。
  static const List<(String, String)> searchModePresets = <(String, String)>[
    ('auto', '自动：Tavily → Bing 直连 → 浏览器，依次尝试'),
    ('tavily', '只用 Tavily（需要 API Key）'),
    ('browser', '只用内置浏览器抓取'),
  ];

  // ------------------------------------------------------------ 识图

  /// 视觉模型（OpenAI 兼容）。留空则只使用本地 OCR。
  String visionBaseUrl = '';
  String visionApiKey = '';
  String visionModel = 'qwen-vl-max';

  // ------------------------------------------------------------ 行为

  /// 只读命令是否自动执行（关闭后所有命令都要确认）
  bool autoApproveSafe = true;

  /// 是否优先用系统悬浮窗做确认。
  /// 工具常常把别的应用切到前台，此时应用内弹窗会被盖住，
  /// 悬浮窗则始终在最上层。需要 SYSTEM_ALERT_WINDOW 权限。
  bool useOverlayConfirm = true;

  /// 是否启用「记忆」：把关于用户的长期事实注入系统提示词。
  ///
  /// 关掉之后**只是不再注入**，记忆条目本身仍然留着 ——
  /// 用户想"暂时别带上这些"和"把记下来的删掉"是两件事，
  /// 混成一个开关会让人不敢碰它。
  bool memoryEnabled = true;

  /// 工作空间目录。空字符串 = 用默认目录。
  ///
  /// **所有工作的中间产物都落在这里**：截图、录屏、附件、插件脚本。
  /// 之所以让用户可选，是因为默认目录在
  /// `/sdcard/Android/data/<包名>/files/dsh` —— 那个位置在文件管理器里
  /// 常常是隐藏的，想自己翻一下截图都找不到。换到「下载」这种可见目录
  /// 就能直接看。
  ///
  /// 注意它**不是**应用内部数据目录：会话、笔记、设置仍然在应用私有目录里，
  /// 不受这里影响。把应用数据也搬到用户可写目录，等于把数据放在谁都
  /// 能改的地方。
  String workspacePath = '';

  // ---------------------------------------------------------------- TeenSpace
  //
  // 内容尺度的三档敏感度。0 = 宽松，1 = 标准，2 = 严格。
  //
  // 这三项**不是**过滤器 —— 应用没法可靠地在本地判断什么算"政治议题"
  // （那需要语义理解，本地没有模型）。它们的真实作用是**写进系统提示词**，
  // 让模型自己按这个尺度回答。所以措辞上给的是"指导"，不是"拦截"。
  //
  // 诚实地说清这一点很重要：把它做成一个看起来像"内容过滤开关"的东西，
  // 用户会以为打开就万无一失，那是假的。

  /// 成人 / R 级内容
  int teenAdult = 1;

  /// 政治议题
  int teenPolitics = 1;

  /// 题目查询（作业、考试题）
  int teenQuery = 1;

  /// 字体方案：pingfang（苹方，默认）/ sans（系统无衬线）/ serif（Times+宋体）
  /// / mono（等宽）/ custom（用户自己加载的字体文件）
  String fontScheme = 'pingfang';

  /// 用户自己选的字体文件路径（苹方等）。
  ///
  /// 空字符串 = 没选。**存路径而不是把字体拷进应用目录**：字体文件动辄十几 MB，
  /// 而且用户换字体时旧的会一直占着空间。存路径的代价是原文件被删/被移动后
  /// 会失效 —— 那时设置页会显示加载失败并把原因写出来。
  String customFontPath = '';

  /// 字号额外放大倍数（1.0 ~ 1.4）。
  /// 主题的基础倍率是 1.0（见 AppFonts.baseScale），最终倍率 = 1.0 × 这个值。
  double fontScale = 1.0;

  void _read() {
    apiKey = _prefs.getString('apiKey') ?? '';
    baseUrl = _prefs.getString('baseUrl') ?? 'https://api.deepseek.com';
    model = _prefs.getString('model') ?? 'deepseek-flash';
    thinkingEnabled = _prefs.getBool('thinkingEnabled') ?? true;
    reasoningEffort = _prefs.getString('reasoningEffort') ?? 'high';
    temperature = _prefs.getDouble('temperature') ?? 0.7;
    maxToolRounds = _prefs.getInt('maxToolRounds') ?? 8;
    searchApiKey = _prefs.getString('searchApiKey') ?? '';
    searchEngine = _prefs.getString('searchEngine') ?? 'bing';
    webSearchMode = _prefs.getString('webSearchMode') ?? 'auto';
    selfHostedSearchUrl = _prefs.getString('selfHostedSearchUrl') ?? '';
    visionBaseUrl = _prefs.getString('visionBaseUrl') ?? '';
    visionApiKey = _prefs.getString('visionApiKey') ?? '';
    visionModel = _prefs.getString('visionModel') ?? 'deepseek-flash';
    autoApproveSafe = _prefs.getBool('autoApproveSafe') ?? true;
    useOverlayConfirm = _prefs.getBool('useOverlayConfirm') ?? true;
    fontScheme = _prefs.getString('fontScheme') ?? 'pingfang';
    customFontPath = _prefs.getString('customFontPath') ?? '';
    memoryEnabled = _prefs.getBool('memoryEnabled') ?? true;
    workspacePath = _prefs.getString('workspacePath') ?? '';
    teenAdult = _prefs.getInt('teenAdult') ?? 1;
    teenPolitics = _prefs.getInt('teenPolitics') ?? 1;
    teenQuery = _prefs.getInt('teenQuery') ?? 1;
    fontScale = _prefs.getDouble('fontScale') ?? 1.0;
  }

  Future<void> update(void Function() mutate) async {
    mutate();
    notifyListeners();

    await _prefs.setString('apiKey', apiKey);
    await _prefs.setString('baseUrl', baseUrl);
    await _prefs.setString('model', model);
    await _prefs.setBool('thinkingEnabled', thinkingEnabled);
    await _prefs.setString('reasoningEffort', reasoningEffort);
    await _prefs.setDouble('temperature', temperature);
    await _prefs.setInt('maxToolRounds', maxToolRounds);
    await _prefs.setString('searchApiKey', searchApiKey);
    await _prefs.setString('searchEngine', searchEngine);
    await _prefs.setString('webSearchMode', webSearchMode);
    await _prefs.setString('selfHostedSearchUrl', selfHostedSearchUrl);
    await _prefs.setString('visionBaseUrl', visionBaseUrl);
    await _prefs.setString('visionApiKey', visionApiKey);
    await _prefs.setString('visionModel', visionModel);
    await _prefs.setBool('autoApproveSafe', autoApproveSafe);
    await _prefs.setBool('useOverlayConfirm', useOverlayConfirm);
    await _prefs.setString('fontScheme', fontScheme);
    await _prefs.setString('customFontPath', customFontPath);
    await _prefs.setBool('memoryEnabled', memoryEnabled);
    await _prefs.setString('workspacePath', workspacePath);
    await _prefs.setInt('teenAdult', teenAdult);
    await _prefs.setInt('teenPolitics', teenPolitics);
    await _prefs.setInt('teenQuery', teenQuery);
    await _prefs.setDouble('fontScale', fontScale);
  }

  bool get configured => apiKey.trim().isNotEmpty;

  /// 把 TeenSpace 的三档敏感度拼成一段注入系统提示词的文字。
  ///
  /// **三档全「标准」时返回空串。** 因为"标准"就是模型的默认行为，
  /// 特意写一段"请保持标准"既白花 token，又可能让模型过度紧张、
  /// 该说的也缩着不说。
  ///
  /// 这段文字是**指导**，不是过滤器 —— 应用没有语义理解能力，
  /// 判断不了"什么算政治议题"。详见 `TeenSpacePage` 的说明。
  String contentPolicyPrompt() {
    final List<String> rules = <String>[];

    if (teenAdult == 2) {
      rules.add('- 性、暴力、血腥的直接描写：拒绝，只给概括，或建议换个方向。');
    } else if (teenAdult == 0) {
      rules.add('- 成人向内容：用户是成年人，按正常尺度回答，不要主动规避。');
    }

    if (teenPolitics == 2) {
      rules.add('- 政治议题：只陈述可考证的事实，**不给立场判断、不做预测**；'
          '存在争议的部分要说明存在争议，不要替用户下结论。');
    } else if (teenPolitics == 0) {
      rules.add('- 政治议题：可以给出分析和立场，不必自我审查。');
    }

    if (teenQuery == 2) {
      rules.add('- 作业 / 考试 / 竞赛题：**不要直接给最终答案**。'
          '讲清思路、点出关键那一步，让用户自己算出来。');
    } else if (teenQuery == 0) {
      rules.add('- 作业 / 考试题：直接给答案和完整过程，不用顾虑。');
    }

    if (rules.isEmpty) return '';

    return '\n内容尺度（用户在 TeenSpace 里设定，优先级高于你自己的默认习惯）：\n'
        '${rules.join('\n')}\n'
        '这是**回答尺度**的指导，不是内容过滤 —— 按它调整你的表达方式即可，'
        '不要向用户复述这段规则。\n';
  }

  /// 当前模型是否具备图像理解能力。
  /// 只有 deepseek-v4-pro 明确不支持；其余（含 flash）都可以。
  bool get modelSeesImages => !model.toLowerCase().contains('pro');

  /// 规范化 base url，容忍用户填/不填 /v1
  String get chatEndpoint {
    String b = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (b.isEmpty) b = 'https://api.deepseek.com';
    return '$b/chat/completions';
  }
}

/// 会话历史，存成一个 JSON 文件。
///
/// 用文件而不是 SharedPreferences：历史会随着使用不断变长，
/// 塞进 key-value 存储里迟早会遇到大小和性能问题。
class ConversationStore extends ChangeNotifier {
  ConversationStore(this._file);

  final File _file;

  final List<Conversation> conversations = <Conversation>[];
  String? currentId;

  Conversation? get current {
    if (currentId == null) return null;
    for (final Conversation c in conversations) {
      if (c.id == currentId) return c;
    }
    return null;
  }

  /// 最近更新的排前面
  List<Conversation> get sorted {
    final List<Conversation> list = List<Conversation>.from(conversations)
      ..sort((Conversation a, Conversation b) =>
          b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Future<void> load() async {
    conversations.clear();
    try {
      if (!await _file.exists()) return;
      final dynamic data = jsonDecode(await _file.readAsString());
      if (data is List) {
        for (final dynamic e in data) {
          conversations
              .add(Conversation.fromJson(Map<String, dynamic>.from(e as Map)));
        }
      }
      currentId = conversations.isEmpty ? null : sorted.first.id;
    } catch (_) {
      // 历史文件损坏时不该阻止 app 启动
      conversations.clear();
      currentId = null;
    }
    notifyListeners();
  }

  Future<void> save() async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(
        jsonEncode(conversations.map((Conversation c) => c.toJson()).toList()),
      );
    } catch (_) {
      // 写失败不致命，下次再试
    }
  }

  Conversation createNew() {
    final Conversation c = Conversation(
      id: newId(),
      title: '新对话',
    );
    conversations.add(c);
    currentId = c.id;
    notifyListeners();
    unawaitedSave();
    return c;
  }

  void select(String id) {
    currentId = id;
    notifyListeners();
  }

  void remove(String id) {
    conversations.removeWhere((Conversation c) => c.id == id);
    if (currentId == id) {
      currentId = conversations.isEmpty ? null : sorted.first.id;
    }
    notifyListeners();
    unawaitedSave();
  }

  void clearAll() {
    conversations.clear();
    currentId = null;
    notifyListeners();
    unawaitedSave();
  }

  /// 用导入的数据整体替换（导入备份的「覆盖」模式用）。
  ///
  /// 放在 store 内部而不是让导入代码直接改列表再调 notifyListeners()：
  /// notifyListeners 是 ChangeNotifier 的 protected 成员，外部调用会被分析器拦下；
  /// 而且 currentId 的重置逻辑也该由 store 自己负责。
  void replaceAll(List<Conversation> next) {
    conversations
      ..clear()
      ..addAll(next);
    currentId = conversations.isEmpty ? null : sorted.first.id;
    notifyListeners();
    unawaitedSave();
  }

  /// 批量追加（导入备份的「合并」模式用）
  void appendMissing(List<Conversation> next) {
    final Set<String> existing =
        conversations.map((Conversation c) => c.id).toSet();
    bool changed = false;
    for (final Conversation c in next) {
      if (existing.contains(c.id)) continue;
      conversations.add(c);
      changed = true;
    }
    if (!changed) return;
    if (currentId == null && conversations.isNotEmpty) {
      currentId = sorted.first.id;
    }
    notifyListeners();
    unawaitedSave();
  }

  /// 用首条用户消息给会话起个名字，方便在历史里认出来
  void touch(Conversation c) {
    c.updatedAt = DateTime.now();
    if (c.title == '新对话') {
      for (final ChatMessage m in c.messages) {
        if (m.role == Role.user && m.content.trim().isNotEmpty) {
          final String t = m.content.trim().replaceAll('\n', ' ');
          c.title = t.length > 18 ? '${t.substring(0, 18)}…' : t;
          break;
        }
      }
    }
    notifyListeners();
  }

  void unawaitedSave() {
    // 故意不 await：调用方通常在 UI 回调里，不想被磁盘 IO 阻塞
    save();
  }
}
