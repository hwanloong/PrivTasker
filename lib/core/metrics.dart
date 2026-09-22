import 'package:flutter/foundation.dart';

/// 运行时性能指标。
///
/// 全局单例，因为埋点分散在搜索缓存、API 客户端、以及 UI 三处，
/// 层层传引用不现实。
///
/// 关于 token 有一条**必须诚实对待**的边界：
/// 只有 API 真的在响应里返回了 `usage` 才是实测值；拿不到时只能本地估算。
/// 估算用的是「CJK 约 1 token/字 + 其余约 1 token/4 字符」这个经验规则，
/// 中文场景够用，但**不是精确值**。UI 上必须把两者区分显示，
/// 否则用户会拿估算值去对账，然后发现对不上。
class AppMetrics extends ChangeNotifier {
  AppMetrics._();

  static final AppMetrics instance = AppMetrics._();

  // ---------------------------------------------------------------- 缓存

  int searchCacheHits = 0;
  int searchCacheMisses = 0;

  int get searchCacheTotal => searchCacheHits + searchCacheMisses;

  /// 命中率；没有查询过时返回 null（0/0 不是 0%，是「没有数据」）
  double? get cacheHitRate =>
      searchCacheTotal == 0 ? null : searchCacheHits / searchCacheTotal;

  void recordSearchCache({required bool hit}) {
    if (hit) {
      searchCacheHits++;
    } else {
      searchCacheMisses++;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- Token

  int promptTokens = 0;
  int completionTokens = 0;
  int reasoningTokens = 0;

  /// 有多少次调用的 token 是 API 实测返回的
  int measuredCalls = 0;

  /// 有多少次拿不到 usage、只能本地估算
  int estimatedCalls = 0;

  int get totalTokens => promptTokens + completionTokens + reasoningTokens;
  int get callCount => measuredCalls + estimatedCalls;

  /// 有没有实测数据。全是估算时 UI 要显示提示。
  bool get hasMeasuredUsage => measuredCalls > 0;

  void recordUsage({
    required int prompt,
    required int completion,
    int reasoning = 0,
    required bool measured,
  }) {
    promptTokens += prompt;
    completionTokens += completion;
    reasoningTokens += reasoning;
    if (measured) {
      measuredCalls++;
    } else {
      estimatedCalls++;
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ 上下文占用

  /// 最近一次请求的上下文 token 数（估算）
  int lastContextTokens = 0;

  /// 模型上下文上限
  int contextLimit = 0;

  /// 占用比例；没有数据时返回 null
  double? get contextRatio => contextLimit <= 0
      ? null
      : (lastContextTokens / contextLimit).clamp(0.0, 1.0);

  void recordContext({required int tokens, required int limit}) {
    lastContextTokens = tokens;
    contextLimit = limit;
    notifyListeners();
  }

  void reset() {
    searchCacheHits = 0;
    searchCacheMisses = 0;
    promptTokens = 0;
    completionTokens = 0;
    reasoningTokens = 0;
    measuredCalls = 0;
    estimatedCalls = 0;
    lastContextTokens = 0;
    contextLimit = 0;
    notifyListeners();
  }

  // ---------------------------------------------------------------- 估算

  /// 估算一段文本的 token 数。
  ///
  /// 规则：CJK 字符约 1 token/字；其余字符约 1 token/4 字符。
  /// 这是粗略经验值，用途只是给用户一个量级感知，不能当计费依据。
  static int estimate(String text) {
    if (text.isEmpty) return 0;
    int cjk = 0;
    int other = 0;
    for (final int r in text.runes) {
      if (_isCjk(r)) {
        cjk++;
      } else {
        other++;
      }
    }
    return cjk + (other / 4).ceil();
  }

  static bool _isCjk(int r) =>
      (r >= 0x1100 && r <= 0x115F) ||
      (r >= 0x2E80 && r <= 0xA4CF) ||
      (r >= 0xAC00 && r <= 0xD7A3) ||
      (r >= 0xF900 && r <= 0xFAFF) ||
      (r >= 0xFE30 && r <= 0xFE6F) ||
      (r >= 0xFF00 && r <= 0xFF60) ||
      (r >= 0xFFE0 && r <= 0xFFE6);

  /// 大数字的可读格式（1.2k / 3.4M）
  static String humanCount(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '${(n / 1000000).toStringAsFixed(2)}M';
  }
}
