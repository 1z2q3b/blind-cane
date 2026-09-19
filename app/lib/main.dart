import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/storage/token_store.dart';
import 'core/theme/app_theme.dart';
import 'features/alert/fullscreen_alert_page.dart';
import 'models/alert.dart';
import 'state/alert_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // TokenStore 依赖 SharedPreferences，必须在 runApp 之前初始化完成：
  // 否则首帧渲染时登录态还是空的，会先闪一下登录页再跳首页
  final store = await TokenStore.create();
  runApp(
    ProviderScope(
      overrides: [tokenStoreProvider.overrideWithValue(store)],
      child: const CaneGuardianApp(),
    ),
  );
}

class CaneGuardianApp extends ConsumerWidget {
  const CaneGuardianApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: '导盲杖家属端',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: router,
      // 全屏告警的触发点放在这里（Navigator 之上、但能拿到 rootNavigatorKey），
      // 这样无论家属当前在哪个页面，收到紧急告警都能被弹到全屏页
      builder: (context, child) =>
          _FullScreenAlertWatcher(child: child ?? const SizedBox.shrink()),
    );
  }
}

class _FullScreenAlertWatcher extends ConsumerStatefulWidget {
  const _FullScreenAlertWatcher({required this.child});

  final Widget child;

  @override
  ConsumerState<_FullScreenAlertWatcher> createState() =>
      _FullScreenAlertWatcherState();
}

class _FullScreenAlertWatcherState
    extends ConsumerState<_FullScreenAlertWatcher> {
  /// 已经弹出过的告警 id。
  ///
  /// 只靠 `fullScreenAlertProvider` 是否为空判断会漏掉一种情况：
  /// 家属手动返回后 provider 已被 dismiss，此时若同一条告警因为
  /// 断线重连被服务端重推一次，就会再弹一次——这不叫「强提醒」，叫骚扰。
  int? _shownAlertId;

  @override
  Widget build(BuildContext context) {
    ref.listen<AlertRecord?>(fullScreenAlertProvider, (previous, next) {
      if (next == null) {
        _shownAlertId = null;
        return;
      }
      if (_shownAlertId == next.id) {
        return;
      }
      _shownAlertId = next.id;
      // 必须等当前帧画完再 push：ref.listen 的回调可能发生在 build 阶段，
      // 此时直接操作 Navigator 会触发「build 期间修改状态」的断言
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final navigator = rootNavigatorKey.currentState;
        if (navigator == null) {
          return;
        }
        navigator.push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => FullScreenAlertPage(alert: next),
          ),
        );
      });
    });

    return widget.child;
  }
}
