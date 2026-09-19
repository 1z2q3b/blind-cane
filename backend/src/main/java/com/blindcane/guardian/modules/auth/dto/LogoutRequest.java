package com.blindcane.guardian.modules.auth.dto;

/** 登出请求。refreshToken 可选，一并拉黑可避免登出后仍能用它换新令牌。 */
public record LogoutRequest(String refreshToken) {
}
