import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 令牌与登录态本地存储。
///
/// 只用 SharedPreferences 而不引入 flutter_secure_storage：
/// MVP 阶段要能在 Chrome 上跑起来做端到端演示，而 secure_storage 在 Web
/// 上没有真正的安全存储（底层还是 localStorage），引入它只会增加平台配置负担
/// 却不带来实际安全收益。**上架前应替换为 Keychain / Keystore 方案。**
class TokenStore {
  TokenStore._(this._prefs);

  static const _kAccessToken = 'auth.accessToken';
  static const _kRefreshToken = 'auth.refreshToken';
  static const _kUserId = 'auth.userId';
  static const _kPhone = 'auth.phone';
  static const _kNickname = 'auth.nickname';
  static const _kNotifyEnabled = 'settings.notifyEnabled';
  static const _kSoundEnabled = 'settings.soundEnabled';
  static const _kCurrentWardId = 'app.currentWardId';

  final SharedPreferences _prefs;

  static Future<TokenStore> create() async {
    return TokenStore._(await SharedPreferences.getInstance());
  }

  String? get accessToken => _prefs.getString(_kAccessToken);
  String? get refreshToken => _prefs.getString(_kRefreshToken);
  int? get userId => _prefs.getInt(_kUserId);
  String? get phone => _prefs.getString(_kPhone);
  String? get nickname => _prefs.getString(_kNickname);

  bool get isLoggedIn => (accessToken ?? '').isNotEmpty;

  /// 通知开关。默认开启——家属装这个 App 的唯一目的就是收告警，
  /// 默认关闭会导致"装完没反应"的严重误解。
  bool get notifyEnabled => _prefs.getBool(_kNotifyEnabled) ?? true;
  bool get soundEnabled => _prefs.getBool(_kSoundEnabled) ?? true;

  /// 最近一次查看的被监护人，用于首页默认选中。
  int? get currentWardId => _prefs.getInt(_kCurrentWardId);

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required int userId,
    required String phone,
    String? nickname,
  }) async {
    await _prefs.setString(_kAccessToken, accessToken);
    await _prefs.setString(_kRefreshToken, refreshToken);
    await _prefs.setInt(_kUserId, userId);
    await _prefs.setString(_kPhone, phone);
    if (nickname != null) {
      await _prefs.setString(_kNickname, nickname);
    }
  }

  /// 刷新令牌后只更新令牌，不动用户资料。
  Future<void> updateTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _prefs.setString(_kAccessToken, accessToken);
    await _prefs.setString(_kRefreshToken, refreshToken);
  }

  Future<void> clear() async {
    await _prefs.remove(_kAccessToken);
    await _prefs.remove(_kRefreshToken);
    await _prefs.remove(_kUserId);
    await _prefs.remove(_kPhone);
    await _prefs.remove(_kNickname);
    await _prefs.remove(_kCurrentWardId);
    // 通知偏好属于设备级设置，登出不清除
  }

  Future<void> setCurrentWardId(int? wardId) async {
    if (wardId == null) {
      await _prefs.remove(_kCurrentWardId);
    } else {
      await _prefs.setInt(_kCurrentWardId, wardId);
    }
  }

  Future<void> setNotifyEnabled(bool value) => _prefs.setBool(_kNotifyEnabled, value);
  Future<void> setSoundEnabled(bool value) => _prefs.setBool(_kSoundEnabled, value);

  @visibleForTesting
  Future<void> clearAllForTest() => _prefs.clear();
}

/// 在 `main()` 里用 `overrideWithValue` 注入已初始化的实例。
final tokenStoreProvider = Provider<TokenStore>(
  (ref) => throw UnimplementedError('tokenStoreProvider 必须在 ProviderScope 中被 override'),
);
