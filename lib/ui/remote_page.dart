import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'home_shell.dart';

/// 「远程控制」。
///
/// **这一页目前只有壳，没有任何功能** —— 这是刻意的。
///
/// 之所以先做一个空页面而不是干脆不做：一个功能要不要做、做成什么样，
/// 放在设置里占一个位置本身就是个决定。空页面把"这里将来会有一件事"
/// 这个意图固定下来，同时**明确写清它现在不能用** ——
/// 比留一个点进去没反应的入口要好。
///
/// 真做起来需要解决的核心问题是**谁来连**：手机在 NAT 后面、没有公网地址，
/// 要远程连上就必须有一个双方都能到达的中转。那不是"加一个页面"，
/// 是引入一个需要长期维护和付费的服务端。所以这一版不做。
class RemotePage extends StatelessWidget {
  const RemotePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);

    return Scaffold(
      backgroundColor: s.isDark ? AppColors.darkBg : AppColors.lightBg,
      body: Column(
        children: <Widget>[
          AppHeader(
            title: '远程控制',
            subtitle: '尚未实现',
            leading: GlassIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              tooltip: '返回',
              size: 38,
              iconSize: 19,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
              children: <Widget>[
                SurfaceCard(
                  color: AppColors.warning.withValues(alpha: 0.10),
                  borderColor: AppColors.warning.withValues(alpha: 0.30),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(Icons.construction_rounded,
                          size: 18, color: AppColors.warning),
                      const SizedBox(width: 10),
                      Expanded(
                        child: mdText(
                          '这一页还没做，**现在没有任何功能**。\n'
                          '先把它放在这里，是为了把位置占住、把设计意图写下来。',
                          style: AppFonts.body(
                              size: 13, color: s.text, height: 1.6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _h(s, '打算做成什么'),
                _p(s, '在电脑浏览器上打开一个地址，就能看到这台手机并操作它 —— '
                    '看屏幕、点按、执行命令，不用把手机拿在手里。'),
                _p(s, '典型场景：手机放在充电器上当常驻设备，人坐在电脑前干活。'),

                const SizedBox(height: 14),
                _h(s, '为什么先不做'),
                _p(s, '手机在 NAT 后面，没有可被外网直接访问的地址。'
                    '要让外面连进来，必须有一个**双方都能到达的中转** —— '
                    '要么自己部署一台服务器，要么用现成的内网穿透服务。'),
                _p(s, '这不是"加一个页面"的工作量，是引入一个需要长期维护、'
                    '可能要付费、而且**一旦做错就是把手机完全交出去**的服务端。'
                    '在没想清楚鉴权和加密之前，先不做。'),

                const SizedBox(height: 14),
                _h(s, '真要做的话，底线是先满足这三条'),
                _p(s, '1. 端到端加密 —— 中转服务器不能看到屏幕内容和命令。'),
                _p(s, '2. 每次连接都要在手机上确认，或者有一个用户自己设的强口令。'),
                _p(s, '3. 能一键断开，并且断开后中转立即失效。'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _h(AppSurface s, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          t,
          style: AppFonts.body(
              size: 14, weight: FontWeight.w600, color: s.text, height: 1.3),
        ),
      );

  Widget _p(AppSurface s, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: mdText(
          t,
          style: AppFonts.body(size: 13, color: s.muted, height: 1.6),
        ),
      );
}
