import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/alert/alert_detail_page.dart';
import '../../features/auth/login_page.dart';
import '../../features/cane/cane_page.dart';
import '../../features/geofence/geofence_page.dart';
import '../../features/home/main_shell.dart';
import '../../features/location/location_page.dart';
import '../../features/track/track_playback_page.dart';
import '../../features/ward/ward_detail_page.dart';
import '../../features/ward/ward_form_page.dart';
import '../../state/auth_state.dart';

/// 全屏告警页的路由名。推送到达时用 [rootNavigatorKey] 直接 push，
/// 不依赖任何页面的 context，这样家属在任意页面（哪怕是二级页面）都能被弹到。
const String fullScreenAlertPath = '/fullscreen-alert';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // go_router 需要一个 Listenable 来决定何时重新求值 redirect。
  // 直接在 provider 里 `ref.watch(authProvider)` 是行不通的：
  // router 一旦重建，整个导航栈都会丢，登录成功后会从登录页"闪"回首页。
  final refresh = _RefreshNotifier();
  ref.listen<AuthState>(authProvider, (previous, next) {
    if (previous?.loggedIn != next.loggedIn) {
      refresh.bump();
    }
  });
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = ref.read(authProvider).loggedIn;
      final atLogin = state.matchedLocation == '/login';
      if (!loggedIn) {
        return atLogin ? null : '/login';
      }
      // 已登录时不该再看到登录页（例如从后台切回来）
      if (atLogin) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const MainShell(),
      ),
      GoRoute(
        path: '/location',
        name: 'location',
        builder: (context, state) => const LocationPage(),
      ),
      // 电子围栏与轨迹回放：二期功能，做成二级页面而不是 Tab——
      // 家属日常看的是位置和告警，围栏是"配置一次长期不动"的东西，
      // 回放也是偶发查看，占 Tab 会稀释首页信息密度。
      GoRoute(
        path: '/geofence',
        name: 'geofence',
        builder: (context, state) => const GeofencePage(),
      ),
      GoRoute(
        path: '/track',
        name: 'track',
        builder: (context, state) => const TrackPlaybackPage(),
      ),
      // 手杖连接：手机作为 BLE 中心直连手杖，同时充当即时避障的观测台。
      // 做成二级页面而不是第四个 Tab，是因为它只在「配手杖 / 排障」时用，
      // 日常家属用不到，多占一个 Tab 反而稀释了首页的信息密度。
      GoRoute(
        path: '/cane',
        name: 'cane',
        builder: (context, state) => const CanePage(),
      ),
      GoRoute(
        path: '/wards/new',
        name: 'ward-new',
        builder: (context, state) => const WardFormPage(),
      ),
      GoRoute(
        path: '/wards/:id',
        name: 'ward-detail',
        builder: (context, state) => WardDetailPage(
          wardId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/wards/:id/edit',
        name: 'ward-edit',
        builder: (context, state) => WardFormPage(
          wardId: int.tryParse(state.pathParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/alerts/:id',
        name: 'alert-detail',
        builder: (context, state) => AlertDetailPage(
          alertId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
    ],
    errorBuilder: (context, state) => _NotFoundPage(location: state.uri.toString()),
  );
});

class _RefreshNotifier extends ChangeNotifier {
  void bump() => notifyListeners();
}

class _NotFoundPage extends StatelessWidget {
  const _NotFoundPage({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('页面不存在')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.link_off, size: 56),
              const SizedBox(height: 16),
              Text('没有找到 $location', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              // 全宽 CTA：主题 minimumSize 宽度为 0，全宽靠 SizedBox 撑
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('返回首页'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
