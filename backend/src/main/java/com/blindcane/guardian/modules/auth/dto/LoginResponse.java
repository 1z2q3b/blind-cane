package com.blindcane.guardian.modules.auth.dto;

/**
 * 登录响应（双令牌）。
 *
 * @param accessToken  访问令牌，有效期 2 小时
 * @param refreshToken 刷新令牌，有效期 7 天
 * @param tokenType    固定 Bearer
 * @param expiresIn    accessToken 剩余有效秒数，App 可据此提前静默刷新
 * @param userInfo     家属账号信息
 */
public record LoginResponse(String accessToken, String refreshToken, String tokenType,
                            long expiresIn, UserInfoVO userInfo) {
}
