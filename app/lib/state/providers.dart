import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../core/storage/token_store.dart';
import '../core/ws/ws_client.dart';
import '../data/guardian_repository.dart';
import 'auth_state.dart';

/// REST 客户端。
///
/// `onSessionExpired` 在令牌刷新失败时触发，用来把本地登录态清掉并踢回登录页。
/// 这里用 `ref.read(...)` 而不是 `ref.watch(...)`：回调是在未来某个时刻执行的，
/// 如果写成 watch 就会让 apiClient 依赖 authProvider，而 authProvider 又依赖
/// repository → apiClient，形成构建期循环依赖。
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    store: ref.watch(tokenStoreProvider),
    onSessionExpired: () {
      ref.read(authProvider.notifier).handleSessionExpired();
    },
  );
});

final repositoryProvider = Provider<GuardianRepository>((ref) {
  return GuardianRepository(ref.watch(apiClientProvider));
});

/// WebSocket 客户端。容器销毁时一并释放，避免热重载后残留旧连接。
final wsClientProvider = Provider<GuardianWsClient>((ref) {
  final client = GuardianWsClient(ref.watch(tokenStoreProvider));
  ref.onDispose(client.dispose);
  return client;
});
