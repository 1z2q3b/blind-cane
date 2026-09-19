/// 登录返回的令牌与用户资料。
class LoginResult {
  const LoginResult({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.userInfo,
  });

  final String accessToken;
  final String refreshToken;

  /// accessToken 有效期（秒）。
  final int expiresIn;
  final UserInfo userInfo;

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    return LoginResult(
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String? ?? '',
      expiresIn: (json['expiresIn'] as num?)?.toInt() ?? 0,
      userInfo: UserInfo.fromJson(
          (json['userInfo'] as Map<String, dynamic>?) ?? const {}),
    );
  }
}

class UserInfo {
  const UserInfo({
    required this.id,
    required this.phone,
    required this.nickname,
    this.avatar,
  });

  final int id;
  final String phone;
  final String nickname;
  final String? avatar;

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: (json['id'] as num?)?.toInt() ?? 0,
      phone: json['phone'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '家属',
      avatar: json['avatar'] as String?,
    );
  }

  /// 手机号打码，列表里展示用。中间四位隐藏是中国用户习惯的隐私表达。
  String get maskedPhone =>
      phone.length == 11 ? '${phone.substring(0, 3)}****${phone.substring(7)}' : phone;
}
