package com.blindcane.guardian.modules.auth.service.impl;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.blindcane.guardian.common.exception.BizException;
import com.blindcane.guardian.common.result.ErrorCode;
import com.blindcane.guardian.framework.config.BlindcaneProperties;
import com.blindcane.guardian.framework.redis.RedisGuard;
import com.blindcane.guardian.framework.security.JwtTokenService;
import com.blindcane.guardian.framework.security.TokenBlacklistService;
import com.blindcane.guardian.modules.auth.dto.LoginRequest;
import com.blindcane.guardian.modules.auth.dto.LoginResponse;
import com.blindcane.guardian.modules.auth.dto.SmsCodeResponse;
import com.blindcane.guardian.modules.auth.dto.UserInfoVO;
import com.blindcane.guardian.modules.auth.service.AuthService;
import com.blindcane.guardian.modules.auth.service.SmsSender;
import com.blindcane.guardian.modules.user.entity.FamilyUser;
import com.blindcane.guardian.modules.user.mapper.FamilyUserMapper;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.time.Duration;

/**
 * 认证服务实现。
 *
 * <p>验证码、发送间隔、每日上限全部放 Redis：
 * 这些数据生命周期短（5 分钟 ~ 1 天），天然适合 TTL 自动清理，
 * 且多实例部署时不需要额外做同步。
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class AuthServiceImpl implements AuthService {

    private static final String KEY_SMS_CODE = "auth:sms:code:";
    private static final String KEY_SMS_INTERVAL = "auth:sms:interval:";
    private static final String KEY_SMS_DAILY = "auth:sms:daily:";
    private static final String TOKEN_TYPE_BEARER = "Bearer";

    private static final SecureRandom RANDOM = new SecureRandom();

    private final FamilyUserMapper familyUserMapper;
    private final StringRedisTemplate redisTemplate;
    private final RedisGuard redisGuard;
    private final SmsSender smsSender;
    private final JwtTokenService jwtTokenService;
    private final TokenBlacklistService tokenBlacklistService;
    private final BlindcaneProperties properties;

    @Override
    public SmsCodeResponse sendSmsCode(String phone) {
        BlindcaneProperties.Sms smsProps = properties.getSms();

        // 1) 每日上限：先占用计数，超限直接拒绝且不写发送间隔（否则用户被白等 60 秒）
        String dailyKey = KEY_SMS_DAILY + phone;
        Long todayCount = redisGuard.call(
                () -> redisTemplate.opsForValue().increment(dailyKey), () -> null);
        if (todayCount == null) {
            // 验证码链路强依赖 Redis，没有缓存就无从校验，必须给出明确业务错误而非 500
            throw BizException.of(ErrorCode.SMS_SERVICE_UNAVAILABLE);
        }
        if (todayCount == 1L) {
            redisGuard.run(() -> redisTemplate.expire(dailyKey, Duration.ofDays(1)));
        }
        if (todayCount > smsProps.getMaxPerDay()) {
            throw BizException.of(ErrorCode.SMS_DAILY_LIMIT);
        }

        // 2) 发送间隔：setIfAbsent 原子占位，天然防并发重复发送
        String intervalKey = KEY_SMS_INTERVAL + phone;
        Boolean acquired = redisGuard.call(() -> redisTemplate.opsForValue()
                .setIfAbsent(intervalKey, "1", Duration.ofSeconds(smsProps.getIntervalSeconds())),
                () -> null);
        if (!Boolean.TRUE.equals(acquired)) {
            throw BizException.of(acquired == null
                    ? ErrorCode.SMS_SERVICE_UNAVAILABLE
                    : ErrorCode.SMS_SEND_TOO_FREQUENT);
        }

        // 3) 生成验证码：真实短信走随机码，Mock 走固定码
        String code = smsProps.isEnabled() ? randomCode() : smsProps.getMockCode();
        Boolean stored = redisGuard.call(() -> {
            redisTemplate.opsForValue().set(KEY_SMS_CODE + phone, code,
                    Duration.ofSeconds(smsProps.getCodeTtlSeconds()));
            return true;
        }, () -> false);
        if (!Boolean.TRUE.equals(stored)) {
            throw BizException.of(ErrorCode.SMS_SERVICE_UNAVAILABLE);
        }
        smsSender.sendCode(phone, code);

        return new SmsCodeResponse(smsSender.isMock(),
                smsSender.isMock() ? code : null,
                smsProps.getCodeTtlSeconds());
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public LoginResponse login(LoginRequest request) {
        String phone = request.phone();
        verifySmsCode(phone, request.smsCode());

        FamilyUser user = familyUserMapper.selectOne(
                Wrappers.<FamilyUser>lambdaQuery().eq(FamilyUser::getPhone, phone));
        if (user == null) {
            user = register(phone);
        }
        assertAccountUsable(user);

        return issueTokens(user);
    }

    @Override
    public LoginResponse refresh(String refreshToken) {
        Claims claims;
        try {
            claims = jwtTokenService.parse(refreshToken);
        } catch (JwtException | IllegalArgumentException e) {
            log.debug("refreshToken 解析失败: {}", e.getMessage());
            throw BizException.of(ErrorCode.REFRESH_TOKEN_INVALID);
        }
        // 类型必须对得上：否则 accessToken 也能拿来换新 token，等于变相延长会话
        if (!JwtTokenService.TYPE_REFRESH.equals(jwtTokenService.extractType(claims))
                || tokenBlacklistService.isBlacklisted(claims.getId())) {
            throw BizException.of(ErrorCode.REFRESH_TOKEN_INVALID);
        }

        FamilyUser user = familyUserMapper.selectById(jwtTokenService.extractUserId(claims));
        if (user == null) {
            throw BizException.of(ErrorCode.REFRESH_TOKEN_INVALID);
        }
        assertAccountUsable(user);

        // 不做 refreshToken 轮换：家属端是多设备场景，轮换会导致同账号其他设备被踢下线。
        // 到期（7 天）后必须重新用验证码登录。
        JwtTokenService.IssuedToken accessToken = jwtTokenService.issueAccessToken(user.getId(), user.getPhone());
        return new LoginResponse(accessToken.token(), refreshToken, TOKEN_TYPE_BEARER,
                accessTokenTtlSeconds(), toUserInfo(user));
    }

    @Override
    public void logout(String accessToken, String refreshToken) {
        blacklistQuietly(accessToken);
        blacklistQuietly(refreshToken);
    }

    // ------------------------------------------------------------------
    // 内部方法
    // ------------------------------------------------------------------

    private void verifySmsCode(String phone, String inputCode) {
        String codeKey = KEY_SMS_CODE + phone;
        String cachedCode = redisGuard.call(
                () -> redisTemplate.opsForValue().get(codeKey), () -> null);
        if (cachedCode == null) {
            // 拿不到缓存：要么确实没发过/已过期，要么 Redis 不可用，两者提示必须区分
            throw BizException.of(redisGuard.available()
                    ? ErrorCode.SMS_CODE_EXPIRED
                    : ErrorCode.SMS_SERVICE_UNAVAILABLE);
        }
        if (!cachedCode.equals(inputCode)) {
            // 输错不删验证码，允许用户重新输入，但仍受后续登录尝试次数约束
            throw BizException.of(ErrorCode.SMS_CODE_ERROR);
        }
        // 校验成功后立即失效，防止同一验证码被重复使用
        redisGuard.run(() -> redisTemplate.delete(codeKey));
    }

    private FamilyUser register(String phone) {
        FamilyUser user = new FamilyUser();
        user.setPhone(phone);
        // 默认昵称用尾号，家属首次登录后可在设置页修改
        user.setNickname("家属" + phone.substring(phone.length() - 4));
        user.setStatus(FamilyUser.STATUS_NORMAL);
        familyUserMapper.insert(user);
        log.info("新家属注册成功: userId={}, phone={}", user.getId(), phone);
        return user;
    }

    private void assertAccountUsable(FamilyUser user) {
        if (user.getStatus() != null && user.getStatus() == FamilyUser.STATUS_DISABLED) {
            throw BizException.of(ErrorCode.ACCOUNT_DISABLED);
        }
    }

    private LoginResponse issueTokens(FamilyUser user) {
        JwtTokenService.IssuedToken accessToken = jwtTokenService.issueAccessToken(user.getId(), user.getPhone());
        JwtTokenService.IssuedToken refreshToken = jwtTokenService.issueRefreshToken(user.getId(), user.getPhone());
        return new LoginResponse(accessToken.token(), refreshToken.token(), TOKEN_TYPE_BEARER,
                accessTokenTtlSeconds(), toUserInfo(user));
    }

    private UserInfoVO toUserInfo(FamilyUser user) {
        return new UserInfoVO(user.getId(), user.getPhone(), user.getNickname(), user.getAvatar());
    }

    private long accessTokenTtlSeconds() {
        return properties.getJwt().getAccessTokenTtlMinutes() * 60;
    }

    /** 登出时令牌本身可能已过期或非法，此时无需拉黑，忽略即可。 */
    private void blacklistQuietly(String token) {
        if (token == null || token.isBlank()) {
            return;
        }
        try {
            Claims claims = jwtTokenService.parse(token);
            tokenBlacklistService.blacklist(claims.getId(), jwtTokenService.extractExpiration(claims));
        } catch (JwtException | IllegalArgumentException e) {
            log.debug("登出时忽略非法/过期令牌: {}", e.getMessage());
        }
    }

    private String randomCode() {
        return String.format("%06d", RANDOM.nextInt(1_000_000));
    }
}
