import 'dart:convert';

/// 风险等级。
///
/// 这是整个 app 的安全基线：**只有白名单内的只读命令才是 [safe]**，
/// 认不出来的一律落到 [caution]，宁可多问一次，也不静默执行。
enum RiskLevel {
  /// 明确的只读命令，直接执行
  safe,

  /// 无法确认安全，或会改变可逆状态 —— 需要确认
  caution,

  /// 破坏性、不可撤销 —— 需要确认，且默认按钮是「拒绝」
  dangerous,
}

extension RiskLevelX on RiskLevel {
  String get label => switch (this) {
        RiskLevel.safe => '只读',
        RiskLevel.caution => '需确认',
        RiskLevel.dangerous => '危险',
      };

  /// 是否需要弹窗确认
  bool get needsConfirm => this != RiskLevel.safe;
}

/// 风险判定结果：等级 + 人话解释「为什么危险」。
/// 把理由展示给用户是这套机制的关键——只弹「是否继续」等于没提示。
class RiskAssessment {
  const RiskAssessment(this.level, this.reasons);

  final RiskLevel level;
  final List<String> reasons;

  static const RiskAssessment safe = RiskAssessment(RiskLevel.safe, <String>[]);

  bool get isDangerous => level == RiskLevel.dangerous;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'level': level.name,
        'reasons': reasons,
      };

  static RiskAssessment fromJson(Map<String, dynamic> j) => RiskAssessment(
        RiskLevel.values.firstWhere(
          (RiskLevel e) => e.name == j['level'],
          orElse: () => RiskLevel.caution,
        ),
        (j['reasons'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList(),
      );
}

/// 一次工具调用的状态
enum InvocationStatus {
  /// 等待用户确认
  awaitingConfirm,
  running,
  success,
  failed,

  /// 用户点了拒绝
  rejected,
}

/// 一次具体的工具调用
class ToolInvocation {
  ToolInvocation({
    required this.id,
    required this.name,
    required this.argumentsJson,
    required this.args,
    required this.risk,
    this.status = InvocationStatus.awaitingConfirm,
    this.output,
  });

  /// 对应 API 的 tool_call id
  final String id;
  final String name;

  /// 原始 JSON 字符串（回传给模型时必须原样带上）
  final String argumentsJson;
  final Map<String, dynamic> args;
  final RiskAssessment risk;

  InvocationStatus status;
  String? output;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'argumentsJson': argumentsJson,
        'args': args,
        'risk': risk.toJson(),
        'status': status.name,
        'output': output,
      };

  static ToolInvocation fromJson(Map<String, dynamic> j) => ToolInvocation(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        argumentsJson: j['argumentsJson']?.toString() ?? '{}',
        args: Map<String, dynamic>.from(
            (j['args'] as Map?) ?? <String, dynamic>{}),
        risk: RiskAssessment.fromJson(
            Map<String, dynamic>.from((j['risk'] as Map?) ?? <String, dynamic>{})),
        status: InvocationStatus.values.firstWhere(
          (InvocationStatus e) => e.name == j['status'],
          orElse: () => InvocationStatus.success,
        ),
        output: j['output']?.toString(),
      );
}

/// 附件类型
enum AttachmentKind {
  /// 图片：交给模型的图像理解
  image,

  /// 本地文件：文本类会读出内容拼进消息
  file,

  /// 网页 / 接口：插入时抓取内容并随消息一起发给模型
  web,
}

/// 随消息一起发出的附件。
///
/// 图片会作为 image 内容块交给支持图像理解的模型；
/// 文本类文件则把内容读出来拼进文本里；
/// 网页/接口在**插入时就抓取**并把内容存下来——
/// 这样历史记录不需要重新联网，也不会因为原页面改版而对不上。
class Attachment {
  Attachment({
    required this.kind,
    required this.path,
    required this.name,
    this.mime = '',
    this.size = 0,
    this.content = '',
  });

  final AttachmentKind kind;

  /// 本地绝对路径；[AttachmentKind.web] 时存的是原始网址。
  /// 图片会被复制到应用私有目录，避免系统清理缓存后历史记录里的图失效。
  String path;
  String name;
  String mime;
  int size;

  /// 仅 [AttachmentKind.web] 使用：抓取到的正文/JSON（已截断）
  String content;

  bool get isImage => kind == AttachmentKind.image;
  bool get isWeb => kind == AttachmentKind.web;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind.name,
        'path': path,
        'name': name,
        'mime': mime,
        'size': size,
        'content': content,
      };

  static Attachment fromJson(Map<String, dynamic> j) {
    final String? kindName = j['kind']?.toString();
    final AttachmentKind kind = kindName == null
        // 兼容早期只存了 isImage 布尔值的记录
        ? (j['isImage'] == true ? AttachmentKind.image : AttachmentKind.file)
        : AttachmentKind.values.firstWhere(
            (AttachmentKind e) => e.name == kindName,
            orElse: () => AttachmentKind.file,
          );

    return Attachment(
      kind: kind,
      path: j['path']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      mime: j['mime']?.toString() ?? '',
      size: (j['size'] as num?)?.toInt() ?? 0,
      content: j['content']?.toString() ?? '',
    );
  }
}

enum Role { user, assistant, system, tool }

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    this.content = '',
    this.reasoning = '',
    List<ToolInvocation>? tools,
    List<Attachment>? attachments,
    DateTime? createdAt,
    this.pending = false,
    this.error,
  })  : tools = tools ?? <ToolInvocation>[],
        attachments = attachments ?? <Attachment>[],
        createdAt = createdAt ?? DateTime.now();

  final String id;
  final Role role;
  String content;

  /// 思维链（`reasoning_content`）。
  ///
  /// **必须在多轮里原样回传**：DeepSeek 文档明确规定，请求一旦携带 `tools`，
  /// 历史轮次的 reasoning_content 都要回传，否则 API 返回 400。
  /// 所以它不能只当展示用的临时数据，得跟着会话一起持久化。
  String reasoning;

  final List<ToolInvocation> tools;
  final List<Attachment> attachments;
  final DateTime createdAt;

  /// 正在流式输出
  bool pending;
  String? error;

  bool get isEmptyAssistant =>
      role == Role.assistant && content.trim().isEmpty && tools.isEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'role': role.name,
        'content': content,
        'reasoning': reasoning,
        'tools': tools.map((ToolInvocation t) => t.toJson()).toList(),
        'attachments':
            attachments.map((Attachment a) => a.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'error': error,
      };

  static ChatMessage fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
        role: Role.values.firstWhere(
          (Role e) => e.name == j['role'],
          orElse: () => Role.assistant,
        ),
        content: j['content']?.toString() ?? '',
        reasoning: j['reasoning']?.toString() ?? '',
        tools: ((j['tools'] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic e) =>
                ToolInvocation.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        attachments: ((j['attachments'] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic e) =>
                Attachment.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        createdAt:
            DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
        error: j['error']?.toString(),
      );
}

/// 一个会话（历史记录持久化的单位）
class Conversation {
  Conversation({
    required this.id,
    required this.title,
    List<ChatMessage>? messages,
    DateTime? updatedAt,
  })  : messages = messages ?? <ChatMessage>[],
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  final List<ChatMessage> messages;
  DateTime updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'messages': messages.map((ChatMessage m) => m.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static Conversation fromJson(Map<String, dynamic> j) => Conversation(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '新对话',
        messages: ((j['messages'] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic e) =>
                ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        updatedAt:
            DateTime.tryParse(j['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      );

  String encode() => jsonEncode(toJson());
}
