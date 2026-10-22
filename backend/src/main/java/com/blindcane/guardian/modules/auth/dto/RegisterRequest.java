package com.blindcane.guardian.modules.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

/**
 * 注册请求：手机号 + 密码 + 短信验证码。
 *
 * <p>验证码是注册的必经步骤——没有它，任何人都能拿别人的手机号
 * 先把账号占掉（密码登录时代替短信确认「号码归属」的就是这一步）。
 * 注册成功后直接下发双令牌，不需要再调一次登录。
 */
public record RegisterRequest(

        @NotBlank(message = "手机号不能为空")
        @Pattern(regexp = "^1[3-9]\\d{9}$", message = "手机号格式不正确")
        String phone,

        @NotBlank(message = "密码不能为空")
        @Pattern(regexp = "^[0-9A-Za-z]{6,20}$", message = "密码须为 6-20 位字母或数字")
        String password,

        @NotBlank(message = "验证码不能为空")
        @Pattern(regexp = "^\\d{6}$", message = "验证码为 6 位数字")
        String smsCode
) {
}
