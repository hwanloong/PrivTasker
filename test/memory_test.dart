import 'dart:io';

import 'package:dsh_agent/core/memory.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记忆功能的测试。
///
/// 为什么值得单独写一组：记忆的**每一条都会随每一轮对话发给模型**，
/// 所以它的上限、去重、长度限制不是"锦上添花"，而是直接决定
/// 上下文会不会被吃掉 —— 写错了用户只会觉得"越聊越傻"，
/// 完全联想不到是记忆的问题。
void main() {
  late Directory tmp;
  late MemoryStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dsh_memory_test');
    store = await MemoryStore.configure(File('${tmp.path}/memory.json'));
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {
      // 临时目录删不掉不影响测试结论
    }
  });

  test('记一条就能读到', () {
    expect(store.add('用户住在杭州'), isNull);
    expect(store.items.length, 1);
    expect(store.items.first.text, '用户住在杭州');
  });

  test('空内容被拒绝', () {
    expect(store.add('   '), isNotNull);
    expect(store.items, isEmpty);
  });

  test('同一句话不会记两遍', () {
    expect(store.add('用户住在杭州'), isNull);
    expect(store.add('用户住在杭州'), isNull);
    // 第二次是"成功但没新增" —— 模型反复记住同一件事是常态，
    // 不拦的话攒出一堆重复条目，既费上下文又让管理页没法看。
    expect(store.items.length, 1);
  });

  test('超长内容被拒绝，并说明原因', () {
    final String long = '啊' * (MemoryStore.maxLength + 1);
    final String? err = store.add(long);
    expect(err, isNotNull);
    expect(err, contains('太长'));
    expect(store.items, isEmpty);
  });

  test('条数到上限后不再新增', () {
    for (int i = 0; i < MemoryStore.maxItems; i++) {
      expect(store.add('事实 $i'), isNull);
    }
    expect(store.items.length, MemoryStore.maxItems);

    final String? err = store.add('第 ${MemoryStore.maxItems + 1} 条');
    expect(err, isNotNull);
    expect(err, contains('上限'));
    expect(store.items.length, MemoryStore.maxItems);
  });

  test('search 按内容片段定位', () {
    store.add('用户住在杭州');
    store.add('用户常用 Python');
    store.add('用户偏好简洁回答');

    expect(store.search('杭州').single.text, '用户住在杭州');
    expect(store.search('python').single.text, '用户常用 Python',
        reason: '搜索要不区分大小写');
    expect(store.search('不存在的词'), isEmpty);
  });

  test('forget 语义：搜到几条就删几条', () {
    store.add('用户住在杭州');
    store.add('用户在杭州工作');
    store.add('用户常用 Python');

    for (final MemoryItem m in store.search('杭州')) {
      store.remove(m.id);
    }

    expect(store.items.length, 1);
    expect(store.items.single.text, '用户常用 Python');
  });

  test('clear 清空全部', () {
    store.add('a');
    store.add('b');
    store.clear();
    expect(store.items, isEmpty);
  });

  test('关掉开关后不注入；但没记忆时即使开着也不注入', () {
    // 空记忆 + 开着 → 空串。不能插一段空标题，那是白花 token 还干扰模型。
    expect(store.toPromptSection(true), isEmpty);

    store.add('用户住在杭州');

    // 开着 → 有内容，而且带上"这是既知事实"的说明
    final String on = store.toPromptSection(true);
    expect(on, contains('用户住在杭州'));
    expect(on, contains('既知事实'));

    // 关掉 → 完全为空。条目仍然留着（开关只管"要不要带上"，不删数据）。
    expect(store.toPromptSection(false), isEmpty);
    expect(store.items.length, 1, reason: '关开关不能删条目');
  });

  test('写盘的 JSON 能被重新读出来', () async {
    store.add('用户住在杭州');
    store.add('用户常用 Python');
    await store.save();

    // 用同一个文件重新配置一次，模拟"重启应用"
    final MemoryStore reloaded =
        await MemoryStore.configure(File('${tmp.path}/memory.json'));

    expect(reloaded.items.length, 2);
    expect(reloaded.items.first.text, '用户住在杭州');
    expect(reloaded.items.last.text, '用户常用 Python');
    // 时间戳也要能往返，否则管理页的"什么时候记的"会全是今天
    expect(
      reloaded.items.first.createdAt.difference(store.items.first.createdAt),
      lessThan(const Duration(seconds: 1)),
    );
  });

  test('文件损坏时降级成"没有记忆"，不抛异常', () async {
    await File('${tmp.path}/memory.json').writeAsString('{ 这不是 JSON');
    final MemoryStore reloaded =
        await MemoryStore.configure(File('${tmp.path}/memory.json'));
    expect(reloaded.items, isEmpty);
  });
}
