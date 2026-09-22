import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static const List<(String, String)> searchModePresets = <(String, String)>[
    ('auto', '自动：自建 → 服务端 → Tavily → 浏览器，依次尝试'),
    ('selfhosted', '只用自建搜索服务'),
    ('deepseek', '只用 DeepSeek 服务端搜索（web_search）'),
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
  }

  bool get configured => apiKey.trim().isNotEmpty;

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
      id: DateTime.now().microsecondsSinceEpoch.toString(),
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
