// 登录后红屏回归测试。
//
// 现象：登录成功后立即整屏红字（Flutter 错误页），堆栈指向：
//   Provider<WsBridge> 在初始化期间修改了 LocationNotifier 的状态
//   → Riverpod 断言「Providers are not allowed to modify other providers
//     during their initialization」→ 首帧即崩。
//
// 根因：wsBridgeProvider 的 build 里**同步**调用了 bridge.start()，
// start() 又同步执行 _switchWard → locationProvider.reset()，
// 全部发生在 WsBridge 自身的初始化过程中。
//
// 这个断言只在 debug 下拦截（release 会静默放过），所以 flutter test
// 默认的 debug 模式正好能抓住它。
import 'package:cane_guardian/core/storage/token_store.dart';
import 'package:cane_guardian/state/ws_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('wsBridgeProvider 初始化时不修改其它 provider（登录红屏回归）',
      (tester) async {
    await tester.runAsync(() async {
      // 注入已登录会话 + 已选中的被监护人：
      // 这样 bridge.start() 的 _switchWard 会走进 reset 分支，
      // 修复前它正是在这里同步修改 locationProvider 触发断言。
      SharedPreferences.setMockInitialValues({
        'auth.accessToken': 'fake-token',
        'auth.refreshToken': 'fake-refresh',
        'auth.userId': 1,
        'auth.phone': '13800138000',
        'app.currentWardId': 1,
      });
      final store = await TokenStore.create();

      final container = ProviderContainer(overrides: [
        tokenStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container.dispose);

      // 触发构建：修复前这里会抛 ProviderException，
      // 修复后正常返回 WsBridge 实例。
      final bridge = container.read(wsBridgeProvider);
      expect(bridge, isA<WsBridge>());

      // 让 Future.microtask(start) 与内部异步加载跑完，
      // 避免 container.dispose 时还有 pending 微任务
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
  });
}
