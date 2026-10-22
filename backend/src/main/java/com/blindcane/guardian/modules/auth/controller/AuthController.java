package com.blindcane.guardian.modules.auth.controller;

import com.blindcane.guardian.common.result.ApiResponse;
import com.blindcane.guardian.modules.auth.dto.LoginRequest;
import com.blindcane.guardian.modules.auth.dto.LoginResponse;
import com.blindcane.guardian.modules.auth.dto.LogoutRequest;
import com.blindcane.guardian.modules.auth.dto.RefreshTokenRequest;
import com.blindcane.guardian.modules.auth.dto.RegisterRequest;
import com.blindcane.guardian.modules.auth.dto.SendSmsCodeRequest;
import com.blindcane.guardian.modules.auth.dto.SmsCodeResponse;
import com.blindcane.guardian.modules.auth.service.AuthService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpHeaders;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** 认证接口。整个 /api/v1/auth/** 免登录。 */
@Tag(name = "认证", description = "注册（手机号+密码+验证码）；登录支持验证码或密码；Mock 模式下验证码由后端随机生成并回显")
@RestController
@RequestMapping("/api/v1/auth")
@RequiredArgsConstructor
public class AuthController {

    private static final String BEARER_PREFIX = "Bearer ";

    private final AuthService authService;

    @Operation(summary = "发送短信验证码",
            description = "验证码由后端随机生成（6 位），存入 Redis（5 分钟有效，一次性消费）。"
                    + "Mock 模式下响应体回带 mockCode，演示无需查日志。60 秒内同一手机号不可重复发送。")
    @PostMapping("/sms/send")
    public ApiResponse<SmsCodeResponse> sendSmsCode(@Valid @RequestBody SendSmsCodeRequest request) {
        return ApiResponse.success(authService.sendSmsCode(request.phone()));
    }

    @Operation(summary = "注册", description = "手机号 + 密码 + 短信验证码；成功后直接下发 accessToken(2h) + refreshToken(7d)")
    @PostMapping("/register")
    public ApiResponse<LoginResponse> register(@Valid @RequestBody RegisterRequest request) {
        return ApiResponse.success(authService.register(request));
    }

    @Operation(summary = "登录", description = "验证码登录（传 smsCode）或密码登录（传 password），二选一；返回双令牌")
    @PostMapping("/login")
    public ApiResponse<LoginResponse> login(@Valid @RequestBody LoginRequest request) {
        return ApiResponse.success(authService.login(request));
    }

    @Operation(summary = "刷新访问令牌", description = "用 refreshToken 换取新的 accessToken；refreshToken 本身不轮换")
    @PostMapping("/refresh")
    public ApiResponse<LoginResponse> refresh(@Valid @RequestBody RefreshTokenRequest request) {
        return ApiResponse.success(authService.refresh(request.refreshToken()));
    }

    @Operation(summary = "登出", description = "把当前 accessToken 与传入的 refreshToken 加入黑名单，立即失效")
    @PostMapping("/logout")
    public ApiResponse<Void> logout(
            @RequestHeader(value = HttpHeaders.AUTHORIZATION, required = false) String authorization,
            @RequestBody(required = false) LogoutRequest request) {
        String accessToken = authorization != null && authorization.startsWith(BEARER_PREFIX)
                ? authorization.substring(BEARER_PREFIX.length()).trim()
                : null;
        authService.logout(accessToken, request == null ? null : request.refreshToken());
        return ApiResponse.success();
    }
}
