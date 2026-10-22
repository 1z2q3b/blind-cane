import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ws/ws_client.dart';
import '../../state/alert_state.dart';
import '../../state/cane_state.dart';
import '../../state/ws_bridge.dart';
import '../alert/alert_list_page.dart';
import '../settings/settings_page.dart';
import 'home_page.dart';

/// 当前底部 Tab 下标。
///
/// 用 provider 而不是 State 持有，是为了让首页里的「告警中心」入口能直接切 Tab：
/// 如果靠 context 往上找 MainShell 的 State，跨页面复用就会很脆；
/// 状态放在 provider 里，任何页面都能一句 selectTab 完成切换。
class MainTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

final mainTabProvider = NotifierProvider<MainTabNotifier, int>(MainTabNotifier.new);

/// 主框架：底部三个 Tab（首页 / 告警 / 我的）。
///
/// 用 IndexedStack 而不是每次切 Tab 重建页面：
/// 首页里有自绘地图和滚动位置，切到「我的」再切回来如果整个重建，
/// 地图会闪一下、滚动位置会回到顶部，家属会以为数据被刷新了。
class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 在这里激活推送桥：MainShell 是登录后所有页面的共同祖先，
    // 它活着桥就活着，保证在任何二级页面都能收到告警
    ref.watch(wsBridgeProvider);
    // 手杖会话同样必须挂在共同祖先上，不能只在「手杖连接」页里 watch：
    // 命令是走云端广播下来的，如果用户已经切回首页，而 session 那时才被销毁，
    // 订阅就断了 —— 家属点了静音、提示"已下发"，手杖却永远不会动。
    // 挂在这里还能保证 30 秒心跳持续上报，设备不会被云端判离线。
    ref.watch(caneSessionProvider);
    final index = ref.watch(mainTabProvider);
    // 用 asData：value 在 error 态会 rethrow，MainShell 一旦崩掉整个 App 都是空白页
    final pending = ref.watch(pendingCountProvider).asData?.value.total ?? 0;

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: const [
          HomePage(),
          AlertListPage(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) =>
            ref.read(mainTabProvider.notifier).select(value),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pending > 0,
              label: Text('$pending'),
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: pending > 0,
              label: Text('$pending'),
              child: const Icon(Icons.notifications),
            ),
            label: '告警',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

/// WebSocket 连接状态条。断开时明确告知家属「数据可能不是最新的」。
class WsStatusBanner extends ConsumerWidget {
  const WsStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(wsStatusProvider);
    final theme = Theme.of(context);

    if (status != WsStatus.disconnected) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      color: theme.colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.link_off, size: 18, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '实时连接已断开，正在自动重连（每 20 秒轮询兜底）',
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: () => context.push('/location'),
            child: const Text('看位置'),
          ),
        ],
      ),
    );
  }
}
