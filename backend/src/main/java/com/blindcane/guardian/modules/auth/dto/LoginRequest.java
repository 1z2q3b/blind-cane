package com.blindcane.guardian.modules.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

/**
 * 登录请求：验证码登录与密码登录二选一。
 *
 * <ul>
 *   <li>验证码登录：{@code smsCode} 必填（先调 {@code /auth/sms/send} 取码）；</li>
 *   <li>密码登录：{@code password} 必填（账号通过注册流程设置过密码）。</li>
 * </ul>
 *
 * 两者同时传或都不传由 Service 判定并返回 101014——record 的注解校验
 * 表达不了「二选一」这种跨字段约束，放在业务层意图更明确。
 */
public record LoginRequest(

        @NotBlank(message = "手机号不能为空")
        @Pattern(regexp = "^1[3-9]\\d{9}$", message = "手机号格式不正确")
        String phone,

        @Pattern(regexp = "^\\d{6}$", message = "验证码为 6 位数字")
        String smsCode,

        String password
) {
}
