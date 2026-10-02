import '../core/memory.dart';
import '../core/models.dart';
import 'tool.dart';

/// 长期记忆工具。
///
/// **为什么必须有这个工具**：没有它，「记忆」就只是设置页里一个人手填的清单 ——
/// 用户得自己总结自己、自己敲进去。而"agent 记得我"这件事的价值恰恰在于
/// **它自己判断什么值得记**，用户不用管。
///
/// 什么时候该记（这条判断写进了系统提示词，模型看得到）：
/// 会长期有效的信息 —— 住在哪、偏好什么、用什么工具、长期目标。
/// 不该记：一次性任务细节、密钥、已经在笔记里的东西。
class MemoryTool extends AgentTool {
  const MemoryTool();

  @override
  String get name => 'memory';

  @override
  String get title => '记忆';

  @override
  String get description =>
      '你的长期记忆：关于用户的既知事实，每轮对话都会自动带上。\n'
      'action：\n'
      '· list —— 看现在记住了什么。**动手改之前先看一眼，避免重复记。**\n'
      '· add —— 记一条新事实。要短，一句话。会长期有效的才记；'
      '当下这一轮的任务细节不要记。\n'
      '· forget —— 忘掉某条。给它一段关键词（比如"上海"），不是 id。\n'
      '· clear —— 清空全部。只在用户明确说"清空记忆"时用。\n'
      '注意：**绝对不要往记忆里写 API Key、密码、身份证号这类敏感信息** —— '
      '它会随每一轮对话发给模型服务商。';

  @override
  Map<String, dynamic> get parameters => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'action': <String, dynamic>{
            'type': 'string',
            'enum': <String>['list', 'add', 'forget', 'clear'],
            'description': '要做的操作',
          },
          'text': <String, dynamic>{
            'type': 'string',
            'description': 'add 时要记的那句话（一句话，越短越好）',
          },
          'keyword': <String, dynamic>{
            'type': 'string',
            'description': 'forget 时的关键词片段，用来定位要删的那条',
          },
        },
        'required': <String>['action'],
      };

  @override
  RiskAssessment riskFor(Map<String, dynamic> args) {
    // 读和写是两回事：看一眼记忆不改变任何东西，删掉一条则是**不可撤销**的
    // （没有回收站，模型也不会记得原来写了什么）。所以删除要给用户确认。
    switch (args.str('action')) {
      case 'list':
      case 'add':
        return RiskAssessment.safe;
      default:
        return const RiskAssessment(
          RiskLevel.caution,
          <String>['会删除记忆条目，且不可撤销'],
        );
    }
  }

  @override
  String summarize(Map<String, dynamic> args) {
    final String a = args.str('action');
    switch (a) {
      case 'add':
        return '记住：${args.str('text')}';
      case 'forget':
        return '忘掉：${args.str('keyword')}';
      case 'clear':
        return '清空全部记忆';
      default:
        return '查看记忆';
    }
  }

  @override
  Future<String> run(ToolContext ctx, Map<String, dynamic> args) async {
    final MemoryStore store = MemoryStore.instance;

    switch (args.str('action')) {
      case 'list':
        if (store.items.isEmpty) return '（记忆是空的，还没记住任何事）';
        final StringBuffer sb = StringBuffer('当前记忆（${store.items.length} 条）：\n');
        for (final MemoryItem m in store.items) {
          sb.writeln('- ${m.text}');
        }
        return sb.toString();

      case 'add':
        final String? err = store.add(args.str('text'));
        if (err != null) return '没能记住：$err';
        return '记住了。';

      case 'forget':
        final String kw = args.str('keyword');
        final List<MemoryItem> hit = store.search(kw);
        if (hit.isEmpty) return '没有找到含「$kw」的记忆。先用 list 看看有什么。';
        for (final MemoryItem m in hit) {
          store.remove(m.id);
        }
        return '已忘掉 ${hit.length} 条：'
            '${hit.map((MemoryItem m) => m.text).join('；')}';

      case 'clear':
        final int n = store.items.length;
        store.clear();
        return '已清空 $n 条记忆。';

      default:
        return '错误：action 只能是 list / add / forget / clear';
    }
  }
}
