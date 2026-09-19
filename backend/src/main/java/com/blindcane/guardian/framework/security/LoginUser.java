package com.blindcane.guardian.framework.security;

/**
 * 已认证用户。作为 Spring Security 的 principal 放进 SecurityContext，
 * 业务层通过 {@link com.blindcane.guardian.framework.security.CurrentUserHolder} 取出。
 */
public record LoginUser(Long userId, String phone) {
}
