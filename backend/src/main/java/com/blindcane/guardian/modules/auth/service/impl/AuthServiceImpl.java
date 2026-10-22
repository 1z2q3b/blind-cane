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
import com.blindcane.guardian.modules.auth.dto.RegisterRequest;
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
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.security.SecureRandom;
import java.time.Duration;

/**
 * 认证服务实现。
 *
 * <p>验证码、发送间隔、每日上限全部放 Redis：
 * 这些数据生命周期短（5 分钟 ~ 1 天），天然适合 TTL 自动清理，
 * 且多实例部署时不需要额外做同步。
 *
 * <p>登录支持两种方式（二选一）：
 * <ul>
 *   <li><b>验证码登录</b>：证明「当前持有该手机号」，适合忘记密码的场景；</li>
 *   <li><b>密码登录</b>：证明「知道账号的秘密」，适合日常快速进入。</li>
 * </ul>
 * 注册是显式流程（手机号 + 密码 + 验证码），不再有「登录时顺带注册」——
 * 否则密码登录的账号语义会说不通（没设过密码的号码也能进系统）。
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
    private final PasswordEncoder passwordEncoder;

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

        // 3) 生成验证码：**后端随机生成**，Mock 与真实短信同一套逻辑。
        //    之前 Mock 模式用固定码，演示时确实省事，但固定码会让
        //    「发送间隔 / 每日上限 / 一次性消费」这三条防护形同虚设，
        //    且真实联调时行为不一致。随机码的成本只是演示时要看一眼
        //    日志（Mock 实现的 sendCode 会打印，响应体也回显）。
        String code = randomCode();
        Boolean stored = redisGuard.call(() -> {
            redisTemplate.opsForValue().set(KEY_SMS_CODE + phone, code,
                    Duration.ofSeconds(smsProps.getCodeTtlSeconds()));
            return true;
        }, () -> false);
        if (!Boolean.TRUE.equals(stored)) {
            throw BizException.of(ErrorCode.SMS_SERVICE_UNAVAILABLE);
        }
        // Mock 实现只打日志；接入真实短信后由对应实现发送，验证码同样来自这里
        smsSender.sendCode(phone, code);

        return new SmsCodeResponse(smsSender.isMock(),
                smsSender.isMock() ? code : null,
                smsProps.getCodeTtlSeconds());
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public LoginResponse register(RegisterRequest request) {
        String phone = request.phone();
        // 注册也要校验验证码：这是「号码确实在本人手中」的唯一凭据，
        // 没有它，别人可以先用你的手机号注册、设置密码，把你挡在门外
        verifySmsCode(phone, request.smsCode());

        FamilyUser existing = familyUserMapper.selectOne(
                Wrappers.<FamilyUser>lambdaQuery().eq(FamilyUser::getPhone, phone));
        if (existing != null) {
            throw BizException.of(ErrorCode.PHONE_ALREADY_REGISTERED);
        }

        FamilyUser user = new FamilyUser();
        user.setPhone(phone);
        user.setPasswordHash(passwordEncoder.encode(request.password()));
        // 默认昵称用尾号，注册后可在设置页修改
        user.setNickname("家属" + phone.substring(phone.length() - 4));
        user.setStatus(FamilyUser.STATUS_NORMAL);
        familyUserMapper.insert(user);
        log.info("新家属注册成功: userId={}, phone={}", user.getId(), phone);

        // 注册即登录：省掉用户再输一次密码，也让自动化脚本少一次往返
        return issueTokens(user);
    }

    @Override
    public LoginResponse login(LoginRequest request) {
        String phone = request.phone();
        boolean hasSmsCode = StringUtils.hasText(request.smsCode());
        boolean hasPassword = StringUtils.hasText(request.password());
        if (hasSmsCode == hasPassword) {
            // 同时传：不知道用户想用哪种，蒙一个会在另一种失败时给出误导性提示；
            // 都不传：直接告诉他要选一种
            throw BizException.of(ErrorCode.LOGIN_METHOD_REQUIRED);
        }

        FamilyUser user = familyUserMapper.selectOne(
                Wrappers.<FamilyUser>lambdaQuery().eq(FamilyUser::getPhone, phone));
        if (user == null) {
            // 不再自动注册：显式注册才能保证密码登录的账号都有密码
            throw BizException.of(ErrorCode.ACCOUNT_NOT_FOUND);
        }
        assertAccountUsable(user);

        if (hasSmsCode) {
            verifySmsCode(phone, request.smsCode());
        } else {
            assertPasswordMatches(user, request.password());
        }

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
        // 到期（7 天）后必须重新用验证码或密码登录。
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

    /**
     * 密码校验。
     *
     * <p>未设置密码的账号（验证码自动注册时代创建的）走 101013 而不是笼统的
     * 「密码错误」——提示「请用验证码登录」用户知道下一步做什么，
     * 而「密码错误」会让人反复重试一个永远不可能成功的密码。
     */
    private void assertPasswordMatches(FamilyUser user, String rawPassword) {
        if (!StringUtils.hasText(user.getPasswordHash())) {
            throw BizException.of(ErrorCode.PASSWORD_NOT_SET);
        }
        if (!passwordEncoder.matches(rawPassword, user.getPasswordHash())) {
            throw BizException.of(ErrorCode.PASSWORD_ERROR);
        }
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
