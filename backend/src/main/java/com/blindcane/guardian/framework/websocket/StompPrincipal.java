package com.blindcane.guardian.framework.websocket;

import java.security.Principal;

/**
 * STOMP 会话主体。
 *
 * <p>CONNECT 帧校验通过后由 {@link StompAuthChannelInterceptor} 挂到会话上，
 * 后续 SUBSCRIBE 帧通过 {@code accessor.getUser()} 取回，用于校验订阅权限。
 */
public record StompPrincipal(Long userId) implements Principal {

    @Override
    public String getName() {
        return String.valueOf(userId);
    }
}
