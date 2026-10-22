import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_response.dart';
import '../core/storage/token_store.dart';
import '../models/user_info.dart';
import 'providers.dart';

/// 登录态。
///
/// 刻意不用 `AsyncNotifier<AuthState>`：登录页需要同时表达
/// 「正在请求」「请求失败及原因」「已登录」三件事，用 AsyncValue 表达
/// 会变成 `AsyncValue<AuthState>` 这种双层结构，UI 里写起来很绕。
/// 这里把 loading / error 直接放进状态对象，页面逻辑一眼能读懂。
@immutable
class AuthState {
  const AuthState({
    required this.loggedIn,
    this.user,
    this.loading = false,
    this.error,
    this.sessionExpired = false,
  });

  final bool loggedIn;
  final UserInfo? user;
  final bool loading;
  final String? error;

  /// 是否因为令牌失效被动登出——登录页据此提示「登录已过期，请重新登录」，
  /// 而不是含糊地显示成一次普通的登出。
  final bool sessionExpired;

  factory AuthState.fromStore(TokenStore store) {
    if (!store.isLoggedIn) {
      return const AuthState(loggedIn: false);
    }
    final userId = store.userId;
    final phone = store.phone;
    if (userId == null || phone == null) {
      return const AuthState(loggedIn: false);
    }
    return AuthState(
      loggedIn: true,
      user: UserInfo(
        id: userId,
        phone: phone,
        nickname: store.nickname ?? '家属',
      ),
    );
  }

  AuthState copyWith({
    bool? loggedIn,
    UserInfo? user,
    bool? loading,
    String? error,
    bool? sessionExpired,
    bool clearError = false,
    bool clearUser = false,
  }) {
    return AuthState(
      loggedIn: loggedIn ?? this.loggedIn,
      user: clearUser ? null : (user ?? this.user),
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      sessionExpired: sessionExpired ?? this.sessionExpired,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    return AuthState.fromStore(ref.watch(tokenStoreProvider));
  }

  TokenStore get _store => ref.read(tokenStoreProvider);

  /// 发送验证码。返回 Mock 验证码（生产模式下为 null）。
  ///
  /// 验证码由后端随机生成，Mock 模式下响应回显，页面据此自动填入。
  Future<String?> sendSmsCode(String phone) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final result = await ref.read(repositoryProvider).sendSmsCode(phone);
      state = state.copyWith(loading: false);
      return result.mockCode;
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      rethrow;
    }
  }

  /// 注册：手机号 + 密码 + 验证码。成功后直接进入已登录态。
  Future<bool> register({
    required String phone,
    required String password,
    required String smsCode,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final result = await ref
          .read(repositoryProvider)
          .register(phone: phone, password: password, smsCode: smsCode);
      await _persistSession(result);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(loading: false, error: '注册失败：$e');
      return false;
    }
  }

  /// 登录：验证码登录（传 [smsCode]）或密码登录（传 [password]），二选一。
  ///
  /// 注意：手机号不存在时后端**不再自动注册**（返回 101011），
  /// 新用户需要走注册流程——这是为了和密码登录的账号语义保持一致
  /// （没设过密码的号码不该能进系统）。
  Future<bool> login({
    required String phone,
    String? smsCode,
    String? password,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final result = await ref
          .read(repositoryProvider)
          .login(phone: phone, smsCode: smsCode, password: password);
      await _persistSession(result);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(loading: false, error: '登录失败：$e');
      return false;
    }
  }

  /// 登录/注册成功后落盘会话并切状态。
  Future<void> _persistSession(LoginResult result) async {
    await _store.saveSession(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      userId: result.userInfo.id,
      phone: result.userInfo.phone,
      nickname: result.userInfo.nickname,
    );
    state = AuthState(loggedIn: true, user: result.userInfo);
  }

  /// 主动登出：先通知服务端拉黑令牌，再清本地。
  Future<void> logout() async {
    try {
      await ref.read(repositoryProvider).logout();
    } finally {
      await _store.clear();
      state = const AuthState(loggedIn: false);
    }
  }

  /// 令牌刷新失败（由 [ApiClient] 回调触发）。
  void handleSessionExpired() {
    if (!state.loggedIn) {
      return;
    }
    // 这里不能 await 清存储：回调来自网络层，清存储失败也不该阻塞登出流程，
    // 而且登录页判断登录态用的是内存中的 state，本地令牌延迟清理不影响体验。
    _store.clear();
    state = const AuthState(loggedIn: false, sessionExpired: true);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
