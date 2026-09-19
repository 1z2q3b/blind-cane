package com.blindcane.guardian.framework.websocket;

import com.blindcane.guardian.framework.security.JwtTokenService;
import com.blindcane.guardian.framework.security.TokenBlacklistService;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.MessagingException;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.messaging.support.MessageHeaderAccessor;
import org.springframework.stereotype.Component;

import java.security.Principal;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * STOMP 认证与订阅鉴权拦截器。
 *
 * <p>两个阶段：
 * <ol>
 *   <li><b>CONNECT</b>：从帧头 {@code Authorization: Bearer xxx} 解析 JWT，
 *       校验类型/黑名单，通过则把 {@link StompPrincipal} 挂到会话上。</li>
 *   <li><b>SUBSCRIBE</b>：解析 {@code /topic/ward/{wardId}/xxx} 里的 wardId，
 *       校验该会话主体是否是该被监护人的监护人，不通过直接拒绝订阅。</li>
 * </ol>
 *
 * <p><b>为什么必须做第二阶段</b>：仅靠前端不显示入口不是安全边界。
 * 任何登录用户都能手工构造一个 SUBSCRIBE 帧去订阅别人的
 * {@code /topic/ward/123/location}，不做校验就等于位置数据全网广播 ——
 * 这是《个人信息保护法》下的硬性红线，而不是可选的加固项。
 *
 * <p>拒绝方式是抛 {@link MessagingException}：preSend 抛异常后该帧不会进入
 * 消息通道，订阅自然不成立，客户端也收不到任何该主题的消息。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class StompAuthChannelInterceptor implements ChannelInterceptor {

    /** 受管主题：/topic/ward/{wardId}/location|alert|device */
    private static final Pattern WARD_TOPIC = Pattern.compile("^/topic/ward/(\\d+)(?:/.*)?$");
    private static final String AUTHORIZATION_HEADER = "Authorization";
    private static final String BEARER_PREFIX = "Bearer ";

    private final JwtTokenService jwtTokenService;
    private final TokenBlacklistService tokenBlacklistService;
    private final GuardianPermissionChecker guardianPermissionChecker;

    @Override
    public Message<?> preSend(Message<?> message, MessageChannel channel) {
        StompHeaderAccessor accessor = MessageHeaderAccessor.getAccessor(message, StompHeaderAccessor.class);
        if (accessor == null || accessor.getCommand() == null) {
            return message;
        }
        StompCommand command = accessor.getCommand();
        if (StompCommand.CONNECT.equals(command)) {
            handleConnect(accessor);
        } else if (StompCommand.SUBSCRIBE.equals(command)) {
            handleSubscribe(accessor);
        }
        return message;
    }

    private void handleConnect(StompHeaderAccessor accessor) {
        String token = resolveToken(accessor);
        if (token == null) {
            throw new MessagingException("STOMP 连接被拒绝：缺少 Authorization: Bearer <accessToken> 帧头");
        }
        Claims claims;
        try {
            claims = jwtTokenService.parse(token);
        } catch (JwtException | IllegalArgumentException e) {
            throw new MessagingException("STOMP 连接被拒绝：令牌无效或已过期");
        }
        if (!JwtTokenService.TYPE_ACCESS.equals(jwtTokenService.extractType(claims))) {
            // refreshToken 不能用来建立长连接，否则等于把高权限令牌放到客户端长期持有
            throw new MessagingException("STOMP 连接被拒绝：请使用 accessToken");
        }
        if (tokenBlacklistService.isBlacklisted(claims.getId())) {
            throw new MessagingException("STOMP 连接被拒绝：令牌已登出失效");
        }

        Long userId = jwtTokenService.extractUserId(claims);
        accessor.setUser(new StompPrincipal(userId));
        log.info("STOMP 连接认证通过: userId={}, sessionId={}", userId, accessor.getSessionId());
    }

    private void handleSubscribe(StompHeaderAccessor accessor) {
        String destination = accessor.getDestination();
        if (destination == null) {
            return;
        }
        // 允许 /user/** ：这是 Spring 的会话私有目的地，路由时就按 session 隔离，天然安全
        if (destination.startsWith("/user/")) {
            return;
        }

        Matcher matcher = WARD_TOPIC.matcher(destination);
        if (!matcher.matches()) {
            // 白名单策略：只放行已知主题。将来新增主题若忘了加鉴权，会直接订阅失败而不是静默泄露
            throw new MessagingException("订阅被拒绝：不被支持的主题 " + destination);
        }
        Long wardId = Long.valueOf(matcher.group(1));

        Principal principal = accessor.getUser();
        if (!(principal instanceof StompPrincipal stompPrincipal)) {
            throw new MessagingException("订阅被拒绝：会话未认证");
        }
        if (!guardianPermissionChecker.hasPermission(stompPrincipal.userId(), wardId)) {
            log.warn("拒绝订阅: userId={} 非 wardId={} 的监护人, destination={}",
                    stompPrincipal.userId(), wardId, destination);
            throw new MessagingException("订阅被拒绝：无该被监护人的监护权限");
        }
        log.debug("订阅放行: userId={} -> {}", stompPrincipal.userId(), destination);
    }

    private String resolveToken(StompHeaderAccessor accessor) {
        String header = accessor.getFirstNativeHeader(AUTHORIZATION_HEADER);
        if (header == null || !header.startsWith(BEARER_PREFIX)) {
            return null;
        }
        return header.substring(BEARER_PREFIX.length()).trim();
    }
}
