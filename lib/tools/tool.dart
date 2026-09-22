import '../core/models.dart';
import '../core/productivity.dart';
import '../shizuku/shizuku_service.dart';
import 'risk.dart';

/// 工具执行上下文
class ToolContext {
  const ToolContext({
    required this.shizuku,
    required this.workDir,
    required this.searchApiKey,
    required this.visionBaseUrl,
    required this.visionApiKey,
    required this.visionModel,
    required this.mainApiKey,
    required this.mainBaseUrl,
    required this.mainModel,
    required this.modelSeesImages,
    required this.searchEngine,
    required this.webSearchMode,
    required this.selfHostedSearchUrl,
    required this.notes,
    required this.tasks,
  });

  final ShizukuService shizuku;

  /// 应用私有目录：截图、录屏、临时文件都放这里，
  /// 避免污染用户可见的 /sdcard。
  final String workDir;

  /// 笔记与任务。agent 能直接读写它们 —— 这是「常规 agent 功能」的核心：
  /// 用户说「记一下」「明天提醒我」时，模型应该真的写进去，而不是只回一句话。
  final NoteStore notes;
  final TaskStore tasks;

  final String searchApiKey;

  /// 可选的独立视觉模型配置（覆盖主模型）
  final String visionBaseUrl;
  final String visionApiKey;
  final String visionModel;

  /// 主对话模型的信息。识图默认直接走它——
  /// deepseek-flash 本身就支持图像理解，不必再挂第三方视觉模型。
  final String mainApiKey;
  final String mainBaseUrl;
  final String mainModel;
  final bool modelSeesImages;

  /// 内置浏览器抓取搜索时使用的搜索引擎（bing / duckduckgo / baidu / google）
  final String searchEngine;

  /// 联网搜索走哪条通道：auto / deepseek / browser
  final String webSearchMode;

  /// 自建搜索服务地址（agent-web-search 这类）。留空表示未配置。
  final String selfHostedSearchUrl;
}

/// 一个可被模型调用的工具。
abstract class AgentTool {
  const AgentTool();

  /// 给模型看的函数名（英文、下划线）
  String get name;

  /// 给人看的中文名
  String get title;

  /// 给模型看的说明
  String get description;

  /// JSON Schema 形式的参数定义
  Map<String, dynamic> get parameters;

  /// 由工具自己判断本次调用的风险等级。
  /// shell 类工具会走 [RiskClassifier]，其它工具按操作语义给出。
  RiskAssessment riskFor(Map<String, dynamic> args);

  /// 执行并返回给模型看的文本结果
  Future<String> run(ToolContext ctx, Map<String, dynamic> args);

  /// 供 UI 展示的命令/操作摘要
  String summarize(Map<String, dynamic> args) => name;
}

class ToolRegistry {
  ToolRegistry([List<AgentTool>? tools]) : _tools = <AgentTool>[...?tools];

  final List<AgentTool> _tools;

  void register(AgentTool tool) => _tools.add(tool);

  void registerAll(Iterable<AgentTool> tools) => _tools.addAll(tools);

  List<AgentTool> get all => List<AgentTool>.unmodifiable(_tools);

  AgentTool? byName(String name) {
    for (final AgentTool t in _tools) {
      if (t.name == name) return t;
    }
    return null;
  }

  /// 转成 OpenAI / DeepSeek 的 tools 字段
  List<Map<String, dynamic>> toApiSchema() {
    return _tools
        .map((AgentTool t) => <String, dynamic>{
              'type': 'function',
              'function': <String, dynamic>{
                'name': t.name,
                'description': t.description,
                'parameters': t.parameters,
              },
            })
        .toList();
  }
}

/// 参数读取的小工具：模型给的东西不可信，类型和缺失都要兜住。
extension ToolArgs on Map<String, dynamic> {
  String str(String key, {String fallback = ''}) {
    final dynamic v = this[key];
    if (v == null) return fallback;
    return v.toString();
  }

  int intVal(String key, {int fallback = 0}) {
    final dynamic v = this[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? fallback;
  }

  bool boolVal(String key, {bool fallback = false}) {
    final dynamic v = this[key];
    if (v is bool) return v;
    final String s = v?.toString().toLowerCase() ?? '';
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return fallback;
  }
}

/// shell 单引号转义：把 `'` 换成 `'\''`。
/// 模型给的字符串可能含引号/分号，不转义会直接把命令拆坏（既是 bug 也是注入面）。
String shQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// 限制回传给模型的文本长度，避免一次 ls -R 把上下文撑爆
String clampOutput(String s, {int max = 12000}) {
  if (s.length <= max) return s;
  final String head = s.substring(0, max);
  return '$head\n…（输出过长已截断，共 ${s.length} 字符）';
}
