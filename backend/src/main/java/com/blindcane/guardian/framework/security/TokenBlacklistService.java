package com.blindcane.guardian.framework.security;

import com.blindcane.guardian.framework.redis.RedisGuard;
import lombok.RequiredArgsConstructor;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.time.Instant;

/**
 * JWT 黑名单（登出即失效）。
 *
 * <p>为什么用 Redis 而不是给 token 打版本号：登出只影响单个令牌，
 * 版本号方案会把该用户所有设备的会话一起踢掉，与「多家属多设备」场景冲突。
 *
 * <p>TTL 取 token 剩余有效期而非固定值：token 本身过期后黑名单条目就毫无意义，
 * 让它自然过期可以避免 Redis 无界增长。
 */
@Service
@RequiredArgsConstructor
public class TokenBlacklistService {

    private static final String KEY_PREFIX = "auth:blacklist:";

    private final StringRedisTemplate redisTemplate;
    private final RedisGuard redisGuard;

    public void blacklist(String jti, Instant expiresAt) {
        if (jti == null || jti.isBlank()) {
            return;
        }
        long ttlSeconds = Duration.between(Instant.now(), expiresAt).getSeconds();
        if (ttlSeconds > 0) {
            // Redis 不可用时退化为「登出不生效」：拒绝放行会让所有已登录用户被踢下线，
            // 影响面远大于单个令牌延迟失效
            redisGuard.run(() -> redisTemplate.opsForValue()
                    .set(KEY_PREFIX + jti, "1", Duration.ofSeconds(ttlSeconds)));
        }
    }

    public boolean isBlacklisted(String jti) {
        if (jti == null) {
            return false;
        }
        return Boolean.TRUE.equals(redisGuard.call(
                () -> redisTemplate.hasKey(KEY_PREFIX + jti), () -> false));
    }
}
