package com.blindcane.guardian.modules.auth.service;

import com.blindcane.guardian.modules.auth.dto.LoginRequest;
import com.blindcane.guardian.modules.auth.dto.LoginResponse;
import com.blindcane.guardian.modules.auth.dto.RegisterRequest;
import com.blindcane.guardian.modules.auth.dto.SmsCodeResponse;

/**
 * 认证服务：验证码、注册、登录（验证码/密码二选一）、令牌刷新与登出。
 */
public interface AuthService {

    /**
     * 发送短信验证码。验证码由后端随机生成，写入 Redis 并（Mock 模式下）打印到日志。
     * Mock 模式的响应会回带验证码，方便演示与自动化脚本。
     */
    SmsCodeResponse sendSmsCode(String phone);

    /** 注册：手机号 + 密码 + 短信验证码。成功后直接下发双令牌。 */
    LoginResponse register(RegisterRequest request);

    /**
     * 登录：验证码登录或密码登录，二选一（见 {@link LoginRequest}）。
     * 手机号不存在时不再自动注册——注册是显式流程，见 {@link #register}。
     */
    LoginResponse login(LoginRequest request);

    /** 用 refreshToken 换新的 accessToken。 */
    LoginResponse refresh(String refreshToken);

    /** 登出：把 accessToken / refreshToken 加入黑名单立即失效。 */
    void logout(String accessToken, String refreshToken);
}
