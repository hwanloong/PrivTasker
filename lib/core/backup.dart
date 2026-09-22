import 'dart:convert';

import '../plugins/plugin.dart';
import 'models.dart';
import 'productivity.dart';
import 'store.dart';

/// 备份内容
class BackupContents {
  const BackupContents({
    required this.conversations,
    required this.notes,
    required this.tasks,
    required this.plugins,
    this.settings = const <String, dynamic>{},
  });

  final List<Conversation> conversations;
  final List<Note> notes;
  final List<TaskItem> tasks;
  final List<CustomPlugin> plugins;

  /// 只可能包含非敏感项 —— 密钥在导出时就被剥掉了
  final Map<String, dynamic> settings;

  bool get isEmpty =>
      conversations.isEmpty &&
      notes.isEmpty &&
      tasks.isEmpty &&
      plugins.isEmpty;
}

/// 备份的构建与解析。
///
/// 一条硬规则：**API Key 默认不导出**。
/// 备份文件经常被丢进网盘、发给别人、或者传到聊天里，
/// 里面带明文密钥是很容易出事的设计。要带必须显式勾选。
class Backup {
  const Backup._();

  static const int formatVersion = 1;
  static const String appTag = 'privtasker';

  /// 这些设置项永远不进备份
  static const Set<String> _secretKeys = <String>{
    'apiKey',
    'searchApiKey',
    'visionApiKey',
  };

  static Map<String, dynamic> build({
    required List<Conversation> conversations,
    required List<Note> notes,
    required List<TaskItem> tasks,
    required List<CustomPlugin> plugins,
    required Settings settings,
    bool includeSecrets = false,
  }) {
    final Map<String, dynamic> prefs = <String, dynamic>{
      'baseUrl': settings.baseUrl,
      'model': settings.model,
      'thinkingEnabled': settings.thinkingEnabled,
      'reasoningEffort': settings.reasoningEffort,
      'temperature': settings.temperature,
      'maxToolRounds': settings.maxToolRounds,
      'autoApproveSafe': settings.autoApproveSafe,
      'useOverlayConfirm': settings.useOverlayConfirm,
      'searchEngine': settings.searchEngine,
      'webSearchMode': settings.webSearchMode,
      'selfHostedSearchUrl': settings.selfHostedSearchUrl,
      'visionBaseUrl': settings.visionBaseUrl,
      'visionModel': settings.visionModel,
    };

    if (includeSecrets) {
      prefs['apiKey'] = settings.apiKey;
      prefs['searchApiKey'] = settings.searchApiKey;
      prefs['visionApiKey'] = settings.visionApiKey;
    }

    return <String, dynamic>{
      'app': appTag,
      'version': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'includesSecrets': includeSecrets,
      'settings': prefs,
      'conversations':
          conversations.map((Conversation c) => c.toJson()).toList(),
      'notes': notes.map((Note n) => n.toJson()).toList(),
      'tasks': tasks.map((TaskItem t) => t.toJson()).toList(),
      'plugins': plugins.map((CustomPlugin p) => p.toJson()).toList(),
    };
  }

  static String encode(Map<String, dynamic> bundle) =>
      const JsonEncoder.withIndent('  ').convert(bundle);

  /// 解析并做基本校验。抛 [BackupException] 表示文件不可用。
  static BackupContents parse(String raw) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      throw BackupException('不是合法的 JSON 文件：$e');
    }

    if (decoded is! Map) {
      throw BackupException('文件内容不是预期的对象结构');
    }

    final Map<String, dynamic> j = Map<String, dynamic>.from(decoded);

    // 不强校验 app 字段：同一套 schema 也可能被别处复用。
    // 但版本号要挡一下，避免把未来格式当现在格式读。
    final int version = (j['version'] as num?)?.toInt() ?? 1;
    if (version > formatVersion) {
      throw BackupException(
        '备份版本是 $version，高于本应用支持的 $formatVersion，请先升级应用',
      );
    }

    List<T> parseList<T>(
      String key,
      T Function(Map<String, dynamic>) fromJson,
    ) {
      final List<dynamic> raw = (j[key] as List<dynamic>?) ?? <dynamic>[];
      final List<T> out = <T>[];
      for (final dynamic e in raw) {
        if (e is! Map) continue; // 跳过坏条目而不是整体失败
        try {
          out.add(fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {
          // 单条解析失败不影响其它
        }
      }
      return out;
    }

    final Map<String, dynamic> settings = j['settings'] is Map
        ? Map<String, dynamic>.from(j['settings'] as Map)
        : <String, dynamic>{};

    // 再剥一次密钥：即使文件是别人给的、或者被手工改过，
    // 也不让 secret 字段进到内存里被顺手应用。
    for (final String k in _secretKeys) {
      settings.remove(k);
    }

    return BackupContents(
      conversations: parseList<Conversation>('conversations', Conversation.fromJson),
      notes: parseList<Note>('notes', Note.fromJson),
      tasks: parseList<TaskItem>('tasks', TaskItem.fromJson),
      plugins: parseList<CustomPlugin>('plugins', CustomPlugin.fromJson),
      settings: settings,
    );
  }

  /// 应用导入的设置项（只处理非敏感项）
  static Future<void> applySettings(
    Settings settings,
    Map<String, dynamic> data,
  ) async {
    await settings.update(() {
      String? s(String k) => data[k]?.toString();

      bool? b(String k) {
        final dynamic v = data[k];
        if (v is bool) return v;
        return null;
      }

      settings.baseUrl = s('baseUrl') ?? settings.baseUrl;
      settings.model = s('model') ?? settings.model;
      settings.thinkingEnabled = b('thinkingEnabled') ?? settings.thinkingEnabled;
      settings.reasoningEffort =
          s('reasoningEffort') ?? settings.reasoningEffort;
      settings.maxToolRounds =
          (data['maxToolRounds'] as num?)?.toInt() ?? settings.maxToolRounds;
      settings.autoApproveSafe =
          b('autoApproveSafe') ?? settings.autoApproveSafe;
      settings.useOverlayConfirm =
          b('useOverlayConfirm') ?? settings.useOverlayConfirm;
      settings.searchEngine = s('searchEngine') ?? settings.searchEngine;
      settings.webSearchMode = s('webSearchMode') ?? settings.webSearchMode;
      settings.selfHostedSearchUrl =
          s('selfHostedSearchUrl') ?? settings.selfHostedSearchUrl;
      settings.visionBaseUrl =
          s('visionBaseUrl') ?? settings.visionBaseUrl;
      settings.visionModel = s('visionModel') ?? settings.visionModel;
    });
  }

  static String suggestedFileName() {
    final DateTime d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'privtasker-backup-${d.year}${two(d.month)}${two(d.day)}'
        '-${two(d.hour)}${two(d.minute)}.json';
  }
}

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}
