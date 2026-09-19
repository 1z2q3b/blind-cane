package com.blindcane.guardian.modules.auth.service;

import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

/**
 * Mock 短信发送器：只打日志，不真的发短信。
 *
 * <p>默认启用（{@code blindcane.sms.enabled=false} 或未配置时）。
 * 演示时验证码可在后端日志里直接看到，同时 /auth/sms/send 的响应也会回带。
 */
@Slf4j
@Service
@ConditionalOnProperty(name = "blindcane.sms.enabled", havingValue = "false", matchIfMissing = true)
public class MockSmsSender implements SmsSender {

    @Override
    public void sendCode(String phone, String code) {
        log.info("【Mock 短信】手机号 {} 的登录验证码为 {}（有效期以配置为准，演示请直接使用）", phone, code);
    }

    @Override
    public boolean isMock() {
        return true;
    }
}
