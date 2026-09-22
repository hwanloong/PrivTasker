import 'dart:async';

/// 网络错误的翻译与重试。
///
/// 为什么需要这层：底层抛出来的东西长这样——
///   `ClientException with SocketException: Software caused connection abort,
///    uri=https://…`
/// 直接展示给用户等于没说：既看不出哪个环节出问题，也不知道该做什么。
/// 这里统一翻译成「原因 + 该怎么办」。
class NetError {
  const NetError._();

  /// 判断是否是「重试就可能成功」的瞬时错误。
  ///
  /// 注意区分：域名解析失败、证书错误这类重试也没用，不该重试；
  /// 而连接被中断/重置、超时、断管属于典型的瞬时故障。
  static bool isTransient(Object error) {
    final String s = error.toString().toLowerCase();
    return s.contains('software caused connection abort') ||
        s.contains('econnaborted') ||
        s.contains('connection reset') ||
        s.contains('econnreset') ||
        s.contains('broken pipe') ||
        s.contains('epipe') ||
        s.contains('connection closed') ||
        s.contains('connection terminated') ||
        s.contains('timeout') ||
        s.contains('timed out') ||
        s.contains('connection attempt failed');
  }

  /// 把异常翻译成用户能看懂、并且能据此行动的话。
  static String describe(Object error) {
    final String s = error.toString().toLowerCase();

    if (s.contains('software caused connection abort') ||
        s.contains('econnaborted')) {
      return '连接被中断（ECONNABORTED）。连接本来已经建立，却被本机回收了。'
          '常见原因：WiFi 与移动数据之间切换、系统省电限制了后台连接、'
          '或者对方服务器主动断开。通常重试一次就好。';
    }
    if (s.contains('connection reset') || s.contains('econnreset')) {
      return '连接被对方重置（ECONNRESET）。多为服务器或中间设备'
          '（代理、VPN、运营商）主动断开，也可能是触发了对方的风控限流。';
    }
    if (s.contains('broken pipe') || s.contains('epipe')) {
      return '写入时连接已断开（EPIPE）。对方提前关闭了连接。';
    }
    if (s.contains('connection refused')) {
      return '连接被拒绝。目标地址或端口没有服务在监听。';
    }
    if (s.contains('failed host lookup') ||
        s.contains('unknownhost') ||
        s.contains('nodename nor servname')) {
      return '域名解析失败。检查网络是否正常，以及网址有没有写错。';
    }
    if (s.contains('network is unreachable') ||
        s.contains('network unreachable')) {
      return '网络不可达。设备当前没有可用网络，或该地址被网络策略阻断。';
    }
    if (s.contains('timeout') || s.contains('timed out')) {
      return '请求超时。对方在限定时间内没有响应，可能是网络慢或服务繁忙。';
    }
    if (s.contains('certificate') ||
        s.contains('handshake') ||
        s.contains('ssl') ||
        s.contains('tls')) {
      return 'TLS 握手失败。可能是证书问题，或连接被中间设备拦截。';
    }
    if (s.contains('cleartext')) {
      return '明文 HTTP 被系统拦截（Android 9+ 默认禁止）。请改用 https。';
    }
    if (s.contains('403') || s.contains('forbidden')) {
      return '服务器返回 403，拒绝了这次请求。可能是反爬风控或缺权限。';
    }
    if (s.contains('429') || s.contains('too many requests')) {
      return '请求过于频繁被限流（429）。稍等一会儿再试。';
    }
    return error.toString();
  }

  /// 对瞬时网络错误做有限次重试（指数退避）。
  ///
  /// [shouldRetry] 可以让调用方追加自己的判断——例如流式响应在
  /// 已经收到部分内容后就不能重试，否则会把内容重复一遍。
  static Future<T> retry<T>(
    Future<T> Function() action, {
    int attempts = 3,
    Duration baseDelay = const Duration(milliseconds: 700),
    bool Function(Object error)? shouldRetry,
  }) async {
    Object? last;
    for (int i = 0; i < attempts; i++) {
      try {
        return await action();
      } catch (e) {
        last = e;
        final bool canRetry =
            (shouldRetry?.call(e) ?? true) && isTransient(e);
        if (!canRetry || i == attempts - 1) rethrow;
        await Future<void>.delayed(baseDelay * (1 << i));
      }
    }
    throw last!;
  }
}
