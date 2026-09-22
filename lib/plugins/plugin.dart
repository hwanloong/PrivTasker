import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../tools/risk.dart';
import '../tools/tool.dart';

/// 插件类型
enum PluginKind {
  /// 拼出一条 shell 命令交给 Shizuku 执行
  shell,

  /// 发一个 HTTP 请求
  http,
}

/// 插件的一个参数
class PluginParam {
  PluginParam({
    required this.name,
    this.description = '',
    this.required = true,
    this.defaultValue = '',
  });

  /// 注意：这几个字段是**可变的**。
  /// 插件编辑表单直接就地修改这些对象，做成 final 就没法编译。
  String name;
  String description;
  bool required;
  String defaultValue;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'description': description,
        'required': required,
        'defaultValue': defaultValue,
      };

  static PluginParam fromJson(Map<String, dynamic> j) => PluginParam(
        name: j['name']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        required: j['required'] != false,
        defaultValue: j['defaultValue']?.toString() ?? '',
      );
}

/// 用户自定义插件。
///
/// 设计目标：**不写代码就能给 agent 加工具**。
/// 用户只声明「这个工具叫什么、要哪些参数、把这些参数拼成什么命令/请求」，
/// 运行时会被包装成一个标准的 [AgentTool] 注册进工具表，
/// 对模型来说和内置工具没有区别。
class CustomPlugin {
  CustomPlugin({
    required this.id,
    required this.name,
    required this.title,
    this.description = '',
    this.kind = PluginKind.shell,
    this.template = '',
    this.method = 'GET',
    Map<String, String>? headers,
    this.body = '',
    List<PluginParam>? params,
    this.risk = RiskLevel.caution,
    this.enabled = true,
  })  : headers = headers ?? <String, String>{},
        params = params ?? <PluginParam>[];

  final String id;

  /// 函数名：给模型调用用，必须是合法标识符
  String name;
  String title;
  String description;
  PluginKind kind;

  /// shell：命令模板，如 `getprop {{key}}`
  /// http：URL 模板，如 `https://api.example.com/v1/{{path}}`
  String template;

  String method;
  Map<String, String> headers;
  String body;
  List<PluginParam> params;
  RiskLevel risk;
  bool enabled;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'title': title,
        'description': description,
        'kind': kind.name,
        'template': template,
        'method': method,
        'headers': headers,
        'body': body,
        'params': params.map((PluginParam p) => p.toJson()).toList(),
        'risk': risk.name,
        'enabled': enabled,
      };

  static CustomPlugin fromJson(Map<String, dynamic> j) => CustomPlugin(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        kind: PluginKind.values.firstWhere(
          (PluginKind e) => e.name == j['kind'],
          orElse: () => PluginKind.shell,
        ),
        template: j['template']?.toString() ?? '',
        method: j['method']?.toString() ?? 'GET',
        headers: ((j['headers'] as Map?) ?? <String, dynamic>{})
            .map((dynamic k, dynamic v) =>
                MapEntry<String, String>(k.toString(), v.toString())),
        body: j['body']?.toString() ?? '',
        params: ((j['params'] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic e) =>
                PluginParam.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        risk: RiskLevel.values.firstWhere(
          (RiskLevel e) => e.name == j['risk'],
          orElse: () => RiskLevel.caution,
        ),
        enabled: j['enabled'] != false,
      );
}

/// 校验插件定义，返回错误信息；null 表示通过。
String? validatePlugin(CustomPlugin p, {required Iterable<String> takenNames}) {
  if (p.name.trim().isEmpty) return '函数名不能为空';
  if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(p.name)) {
    return '函数名只能包含字母、数字、下划线，且不能以数字开头';
  }
  if (takenNames.contains(p.name)) return '函数名「${p.name}」已被占用';
  if (p.template.trim().isEmpty) return '命令/URL 模板不能为空';

  for (final PluginParam param in p.params) {
    if (param.name.trim().isEmpty) return '存在空参数名';
    if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(param.name)) {
      return '参数名「${param.name}」不合法';
    }
  }
  return null;
}

/// 把 `{{param}}` 替换成实参。
///
/// shell 场景下用 [shQuote] 转义，避免模型给的值里带引号/分号把命令拆坏。
String renderTemplate(
  String template,
  Map<String, dynamic> args,
  List<PluginParam> params, {
  required bool shellEscape,
}) {
  String out = template;
  for (final PluginParam p in params) {
    final dynamic raw = args[p.name];
    final String value =
        raw?.toString() ?? (p.defaultValue.isNotEmpty ? p.defaultValue : '');
    final String replacement =
        shellEscape ? shQuote(value) : Uri.encodeComponent(value);
    out = out.replaceAll('{{${p.name}}}', replacement);
    // 同时支持 {{ name }} 这种带空格的写法
    out = out.replaceAll('{{ ${p.name} }}', replacement);
  }
  return out;
}

/// 把自定义插件适配成标准工具。
class PluginTool extends AgentTool {
  PluginTool(this.plugin);

  final CustomPlugin plugin;

  @override
  String get name => plugin.name;

  @override
  String get title =>
      plugin.title.trim().isEmpty ? plugin.name : plugin.title;

  @override
  String get description {
    final String base =
        plugin.description.trim().isEmpty ? '自定义插件' : plugin.description.trim();
    return '$base（自定义插件，类型：${plugin.kind.name}）';
  }

  @override
  Map<String, dynamic> get parameters => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          for (final PluginParam p in plugin.params)
            p.name: <String, dynamic>{
              'type': 'string',
              'description': p.description,
            },
        },
        'required': plugin.params
            .where((PluginParam p) => p.required && p.defaultValue.isEmpty)
            .map((PluginParam p) => p.name)
            .toList(),
      };

  @override
  RiskAssessment riskFor(Map<String, dynamic> args) {
    if (plugin.risk == RiskLevel.safe) return RiskAssessment.safe;

    // shell 插件：即使用户标了「安全」，也再跑一遍命令分级器。
    // 用户对自己写的模板可能判断失误，这里不能盲信声明。
    if (plugin.kind == PluginKind.shell) {
      final String rendered = renderTemplate(
        plugin.template,
        args,
        plugin.params,
        shellEscape: true,
      );
      final RiskAssessment auto = RiskClassifier.assessShell(rendered);
      if (auto.level.index > plugin.risk.index) return auto;
      if (plugin.risk == RiskLevel.caution) {
        return RiskAssessment(RiskLevel.caution, <String>[
          '执行自定义插件「$title」的 shell 模板',
          ...auto.reasons,
        ]);
      }
      return auto;
    }

    if (plugin.risk == RiskLevel.dangerous) {
      return RiskAssessment(RiskLevel.dangerous, <String>[
        '执行自定义插件「$title」',
      ]);
    }
    return RiskAssessment(RiskLevel.caution, <String>[
      '执行自定义插件「$title」',
    ]);
  }

  @override
  String summarize(Map<String, dynamic> args) {
    if (plugin.kind == PluginKind.shell) {
      return renderTemplate(plugin.template, args, plugin.params,
          shellEscape: true);
    }
    return renderTemplate(plugin.template, args, plugin.params,
        shellEscape: false);
  }

  @override
  Future<String> run(ToolContext ctx, Map<String, dynamic> args) async {
    if (plugin.kind == PluginKind.shell) {
      final String cmd = renderTemplate(plugin.template, args, plugin.params,
          shellEscape: true);
      final r = await ctx.shizuku.exec(cmd, timeoutMs: 30000);
      return 'exit=${r.code}\n${clampOutput(r.output.trim())}';
    }

    // HTTP 插件
    try {
      final String url = renderTemplate(plugin.template, args, plugin.params,
          shellEscape: false);
      final Uri? uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) return '错误：URL 不合法 —— $url';

      final String renderedBody = plugin.body.isEmpty
          ? ''
          : renderTemplate(plugin.body, args, plugin.params,
              shellEscape: false);

      final Map<String, String> hdrs = <String, String>{
        ...plugin.headers,
      };
      if (renderedBody.isNotEmpty &&
          !hdrs.keys.any((String k) => k.toLowerCase() == 'content-type')) {
        hdrs['Content-Type'] = 'application/json';
      }

      final String m = plugin.method.toUpperCase();
      late http.Response resp;

      if (m == 'GET') {
        resp = await http
            .get(uri, headers: hdrs)
            .timeout(const Duration(seconds: 30));
      } else if (m == 'POST') {
        resp = await http
            .post(uri, headers: hdrs, body: renderedBody)
            .timeout(const Duration(seconds: 30));
      } else if (m == 'PUT') {
        resp = await http
            .put(uri, headers: hdrs, body: renderedBody)
            .timeout(const Duration(seconds: 30));
      } else if (m == 'DELETE') {
        resp = await http
            .delete(uri, headers: hdrs, body: renderedBody)
            .timeout(const Duration(seconds: 30));
      } else {
        return '错误：不支持的 method「$m」';
      }

      return 'HTTP ${resp.statusCode}\n'
          '${clampOutput(utf8.decode(resp.bodyBytes, allowMalformed: true), max: 8000)}';
    } catch (e) {
      return '插件执行出错：$e';
    }
  }
}

/// 插件仓库：负责加载/保存/导出。
class PluginStore extends ChangeNotifier {
  PluginStore(this._file);

  final File _file;

  final List<CustomPlugin> plugins = <CustomPlugin>[];

  Future<void> load() async {
    plugins.clear();
    try {
      if (!await _file.exists()) return;
      final dynamic data = jsonDecode(await _file.readAsString());
      if (data is List) {
        for (final dynamic e in data) {
          plugins.add(CustomPlugin.fromJson(Map<String, dynamic>.from(e as Map)));
        }
      }
    } catch (_) {
      // 文件损坏时不让 app 起不来，直接当空列表
    }
    notifyListeners();
  }

  Future<void> save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      jsonEncode(plugins.map((CustomPlugin p) => p.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> saveQuietly() async {
    try {
      await save();
    } catch (_) {
      // 写失败不致命
    }
  }

  /// 当前可用的工具（仅启用的）
  List<PluginTool> enabledTools() => plugins
      .where((CustomPlugin p) => p.enabled)
      .map((CustomPlugin p) => PluginTool(p))
      .toList();
}
