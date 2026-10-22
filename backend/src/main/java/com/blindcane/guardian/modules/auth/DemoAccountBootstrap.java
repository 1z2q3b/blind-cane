package com.blindcane.guardian.modules.auth;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.blindcane.guardian.modules.user.entity.FamilyUser;
import com.blindcane.guardian.modules.user.mapper.FamilyUserMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

/**
 * 演示家属账号引导：启动时确保演示账号存在且两种登录方式都可用。
 *
 * <p>与 {@code DeviceSimulatorBootstrap} 同一个套路：幂等、只服务于演示、
 * 关掉 {@code blindcane.simulator.enabled} 后整块不注册。
 *
 * <p>为什么需要补密码：演示账号 {@code 13800138000} 在旧版「验证码自动注册」
 * 时代就存在于各开发库里，password_hash 是 V3 迁移补的默认空串——
 * 不补密码的话，演示时想展示「密码登录」会撞 101013。
 * 真实环境里账号由注册流程创建，本类不参与。
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnProperty(name = "blindcane.simulator.enabled", havingValue = "true", matchIfMissing = true)
public class DemoAccountBootstrap implements ApplicationRunner {

    /** 演示手机号。与各验证脚本、README 的口径保持一致。 */
    public static final String DEMO_PHONE = "13800138000";

    /** 演示密码。仅用于无真实账号体系的演示环境，生产 profile 下本类不生效。 */
    public static final String DEMO_PASSWORD = "123456";

    private final FamilyUserMapper familyUserMapper;
    private final PasswordEncoder passwordEncoder;

    @Override
    public void run(ApplicationArguments args) {
        FamilyUser user = familyUserMapper.selectOne(
                Wrappers.<FamilyUser>lambdaQuery().eq(FamilyUser::getPhone, DEMO_PHONE));
        if (user == null) {
            user = new FamilyUser();
            user.setPhone(DEMO_PHONE);
            user.setNickname("家属" + DEMO_PHONE.substring(DEMO_PHONE.length() - 4));
            user.setPasswordHash(passwordEncoder.encode(DEMO_PASSWORD));
            user.setStatus(FamilyUser.STATUS_NORMAL);
            familyUserMapper.insert(user);
            log.info("演示家属账号已创建: phone={}, 默认密码 {}", DEMO_PHONE, DEMO_PASSWORD);
            return;
        }
        if (user.getPasswordHash() == null || user.getPasswordHash().isBlank()) {
            FamilyUser patch = new FamilyUser();
            patch.setId(user.getId());
            patch.setPasswordHash(passwordEncoder.encode(DEMO_PASSWORD));
            familyUserMapper.updateById(patch);
            log.info("演示家属账号已补齐默认密码: phone={}, 密码 {}", DEMO_PHONE, DEMO_PASSWORD);
            return;
        }
        log.info("演示家属账号已存在: phone={}, userId={}", DEMO_PHONE, user.getId());
    }
}
