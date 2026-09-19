package com.blindcane.guardian.modules.auth.service;

import com.blindcane.guardian.modules.auth.dto.LoginRequest;
import com.blindcane.guardian.modules.auth.dto.LoginResponse;
import com.blindcane.guardian.modules.auth.dto.SmsCodeResponse;

/** 认证服务：验证码、登录注册、令牌刷新与登出。 */
public interface AuthService {

    /** 发送登录验证码。 */
    SmsCodeResponse sendSmsCode(String phone);

    /** 登录；手机号不存在时自动注册。 */
    LoginResponse login(LoginRequest request);

    /** 用 refreshToken 换新的 accessToken。 */
    LoginResponse refresh(String refreshToken);

    /** 登出：把 accessToken / refreshToken 加入黑名单立即失效。 */
    void logout(String accessToken, String refreshToken);
}
