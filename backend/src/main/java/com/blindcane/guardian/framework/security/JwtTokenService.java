package com.blindcane.guardian.framework.security;

import com.blindcane.guardian.framework.config.BlindcaneProperties;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.stereotype.Service;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import java.util.UUID;

/**
 * JWT 签发与解析服务。
 *
 * <p>用 jjwt 0.12.x 的新 API。0.9.1 那套 {@code Jwts.parser().setSigningKey(String)}
 * 依赖 javax.xml.bind，在 JDK 11+ 必须额外引 jaxb-api，且自定义 Claims 解析容易出
 * UnsupportedJwtException —— 这里直接用 {@code verifyWith(SecretKey).parseSignedClaims()}，
 * 类型安全且不依赖 JAXB。
 *
 * <p>密钥处理：配置里的 secret 原文先做 SHA-256 派生成固定 32 字节，
 * 这样运维随便填多长的字符串都不会触发 {@code WeakKeyException}。
 */
@Service
public class JwtTokenService {

    /** 令牌类型，放进 claim 里，防止 refreshToken 被拿来当 accessToken 用。 */
    public static final String TYPE_ACCESS = "access";
    public static final String TYPE_REFRESH = "refresh";

    private static final String CLAIM_PHONE = "phone";
    private static final String CLAIM_TYPE = "type";

    private final SecretKey secretKey;
    private final BlindcaneProperties.Jwt jwtProps;

    public JwtTokenService(BlindcaneProperties properties) {
        this.jwtProps = properties.getJwt();
        this.secretKey = Keys.hmacShaKeyFor(sha256(jwtProps.getSecret()));
    }

    /** 签发结果：token 原文 + jti（用于黑名单）+ 过期瞬间。 */
    public record IssuedToken(String token, String jti, Instant expiresAt) {
    }

    public IssuedToken issueAccessToken(Long userId, String phone) {
        return issue(userId, phone, TYPE_ACCESS, Instant.now().plus(jwtProps.getAccessTokenTtlMinutes(), ChronoUnit.MINUTES));
    }

    public IssuedToken issueRefreshToken(Long userId, String phone) {
        return issue(userId, phone, TYPE_REFRESH, Instant.now().plus(jwtProps.getRefreshTokenTtlDays(), ChronoUnit.DAYS));
    }

    private IssuedToken issue(Long userId, String phone, String type, Instant expiresAt) {
        String jti = UUID.randomUUID().toString().replace("-", "");
        Instant now = Instant.now();
        String token = Jwts.builder()
                .id(jti)
                .subject(String.valueOf(userId))
                .issuer(jwtProps.getIssuer())
                .claim(CLAIM_PHONE, phone)
                .claim(CLAIM_TYPE, type)
                .issuedAt(Date.from(now))
                .expiration(Date.from(expiresAt))
                .signWith(secretKey)
                .compact();
        return new IssuedToken(token, jti, expiresAt);
    }

    /**
     * 解析并校验签名 / 签发者 / 过期时间。
     *
     * @throws io.jsonwebtoken.JwtException 任何校验失败都抛这个，由调用方翻译成业务错误码
     */
    public Claims parse(String token) {
        return Jwts.parser()
                .verifyWith(secretKey)
                .requireIssuer(jwtProps.getIssuer())
                .build()
                .parseSignedClaims(token)
                .getPayload();
    }

    public Long extractUserId(Claims claims) {
        return Long.valueOf(claims.getSubject());
    }

    public String extractPhone(Claims claims) {
        return claims.get(CLAIM_PHONE, String.class);
    }

    public String extractType(Claims claims) {
        return claims.get(CLAIM_TYPE, String.class);
    }

    public Instant extractExpiration(Claims claims) {
        return claims.getExpiration().toInstant();
    }

    private static byte[] sha256(String raw) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(raw.getBytes(StandardCharsets.UTF_8));
        } catch (NoSuchAlgorithmException e) {
            // SHA-256 是 JDK 必备算法，走不到这里
            throw new IllegalStateException("当前 JDK 不支持 SHA-256", e);
        }
    }
}
