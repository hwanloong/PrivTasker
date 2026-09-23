import '../core/models.dart';
import '../core/rules.dart';
import 'tool.dart';

/// 让 agent 能管理**用户自定义规则**（当……的时候，就……）。
///
/// ## 为什么要给 agent 这个能力
///
/// 用户在对话里说的偏好，往往值得变成一条长期规则：
/// 「以后回答都用要点」「问天气先查我的城市」。
/// 如果 agent 只能说"好的我记住了"，那它下一轮就忘了 ——
/// 因为它并没有真的记住任何东西。
///
/// 有了这个工具，agent 可以把这类偏好**落成真实的规则**，之后每轮都生效。
///
/// ## 安全设计
///
/// **所有写操作都要用户确认。** 两点原因：
///
/// 1. **改规则就是在改 agent 以后的行为** —— 而且是持久的、静默生效的。
///    一条被悄悄插入的规则（比如"回答时先忽略安全提示"）会长期影响所有对话，
///    比一次危险命令更隐蔽。
/// 2. 确认框里会**逐字显示规则内容**，用户能看清自己同意的是什么。
///    所以 riskFor 里的描述必须完整、不能含糊 —— 写"修改一条规则"
///    等于让用户盲签。
///
/// 只有 `list`（读）是自动执行的。
class RuleTool extends AgentTool {
  const RuleTool();

  @override
  String get name => 'rules';

  @override
  String get title => '自定义规则';

  @override
  String get description =>
      '管理用户的自定义规则（形如「当……的时候，就……」）。\n'
      '**什么时候用**：用户表达了希望**以后一直这样**的偏好时 —— '
      '例如「以后回答简短点」「问天气先查我的城市」「发英文先翻译」。\n'
      '这时候**不要只说"好的我记住了"** —— 你下一轮就忘了。'
      '用 create 把它落成一条真实规则，之后每轮对话都会生效。\n'
      '**所有写操作（create/update/delete/toggle）都会弹给用户确认**，'
      '用户可能拒绝。被拒绝时不要重试，也不要说"已经加上了"。\n'
      '不要自作主张加规则 —— 只在用户明确表达长期偏好时才用，'
      '临时要求（"这次简单说"）不要建规则。';

  @override
  Map<String, dynamic> get parameters => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'action': <String, dynamic>{
            'type': 'string',
            'enum': <String>['list', 'create', 'update', 'delete', 'toggle'],
          },
          'id': <String, dynamic>{
            'type': 'string',
            'description': 'update / delete / toggle 时的规则 id（list 结果里能看到）',
          },
          'when': <String, dynamic>{
            'type': 'string',
            'description': '触发条件，例如「我问天气时」。用用户的原话或贴近的说法。',
          },
          'then': <String, dynamic>{
            'type': 'string',
            'description': '要你做的事，例如「先查用户所在城市再回答」',
          },
          'enabled': <String, dynamic>{
            'type': 'boolean',
            'description': 'toggle 时用：true 启用，false 停用',
          },
        },
        'required': <String>['action'],
      };

  /// 找一条规则。抽出来是因为四个写操作都要用。
  static CustomRule? _find(String id) {
    for (final CustomRule r in RuleStore.instance.rules) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// 规则的完整描述，用于确认框和返回值。
  /// **逐字显示内容**是确认框能起作用的前提。
  static String _describe(CustomRule r) => '当${r.when_}时，${r.then_}';

  @override
  RiskAssessment riskFor(Map<String, dynamic> args) {
    final String action = args.str('action');
    final String when = args.str('when').trim();
    final String then = args.str('then').trim();

    switch (action) {
      case 'list':
        return RiskAssessment.safe;

      case 'create':
        return RiskAssessment(RiskLevel.caution, <String>[
          '新增一条长期规则：【当$when时，$then】',
          '这条规则会在之后每一轮对话里生效，直到你手动删掉它',
        ]);

      case 'update':
        final CustomRule? cur = _find(args.str('id'));
        final String before = cur == null ? args.str('id') : _describe(cur);
        return RiskAssessment(RiskLevel.caution, <String>[
          '修改规则：【$before】',
          '改成：【当$when时，$then】',
        ]);

      case 'delete':
        final CustomRule? cur = _find(args.str('id'));
        final String desc = cur == null ? args.str('id') : _describe(cur);
        return RiskAssessment(RiskLevel.caution, <String>[
          '删除规则：【$desc】',
        ]);

      case 'toggle':
        final CustomRule? cur = _find(args.str('id'));
        final String desc = cur == null ? args.str('id') : _describe(cur);
        final bool on = args.boolVal('enabled', fallback: true);
        return RiskAssessment(RiskLevel.caution, <String>[
          '${on ? '启用' : '停用'}规则：【$desc】',
        ]);

      default:
        return RiskAssessment(RiskLevel.caution, <String>['未知操作：$action']);
    }
  }

  @override
  String summarize(Map<String, dynamic> args) {
    final String a = args.str('action');
    if (a == 'create') {
      return '当${args.str('when')}时，${args.str('then')}';
    }
    if (a == 'list') return '列出全部规则';
    return '$a ${args.str('id')}';
  }

  @override
  Future<String> run(ToolContext ctx, Map<String, dynamic> args) async {
    final RuleStore store = RuleStore.instance;
    final String action = args.str('action');

    switch (action) {
      case 'list':
        if (store.rules.isEmpty) return '（用户还没有任何自定义规则）';
        final StringBuffer sb =
            StringBuffer('共 ${store.rules.length} 条：\n');
        for (final CustomRule r in store.rules) {
          // 状态词先取出来存成变量：在单引号字符串的 ${} 里再写单引号，
          // Dart 解析器会提前结束字符串（写这个文件时踩过两次）
          final String state = r.enabled ? '启用' : '停用';
          sb.writeln('- [${r.id}] $state：${_describe(r)}');
        }
        return clampOutput(sb.toString());

      case 'create':
        final String w = args.str('when').trim();
        final String t = args.str('then').trim();
        if (w.isEmpty || t.isEmpty) {
          return '错误：create 需要同时提供 when 和 then';
        }
        final CustomRule r = store.add(w, t);
        return '已新增规则 [${r.id}]：${_describe(r)}\n'
            '（从现在起每一轮对话都会生效）';

      case 'update':
        final CustomRule? r = _find(args.str('id'));
        if (r == null) return '找不到 id 为「${args.str('id')}」的规则。';
        if (args.containsKey('when')) r.when_ = args.str('when').trim();
        if (args.containsKey('then')) r.then_ = args.str('then').trim();
        store.update(r);
        return '已更新规则：${_describe(r)}';

      case 'delete':
        final CustomRule? r = _find(args.str('id'));
        if (r == null) return '找不到 id 为「${args.str('id')}」的规则。';
        final String desc = _describe(r);
        store.remove(r.id);
        return '已删除规则：$desc';

      case 'toggle':
        final CustomRule? r = _find(args.str('id'));
        if (r == null) return '找不到 id 为「${args.str('id')}」的规则。';
        final bool on = args.boolVal('enabled', fallback: true);
        store.toggle(r, on);
        final String word = on ? '启用' : '停用';
        return '已$word规则：${_describe(r)}';

      default:
        return '错误：未知 action「$action」';
    }
  }
}
