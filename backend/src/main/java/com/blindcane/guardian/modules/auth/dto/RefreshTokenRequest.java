package com.blindcane.guardian.modules.auth.dto;

import jakarta.validation.constraints.NotBlank;

/** 刷新 accessToken 请求。 */
public record RefreshTokenRequest(

        @NotBlank(message = "refreshToken 不能为空")
        String refreshToken
) {
}
