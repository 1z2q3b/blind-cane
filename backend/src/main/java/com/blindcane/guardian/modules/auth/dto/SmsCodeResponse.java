package com.blindcane.guardian.modules.auth.dto;

/**
 * 发送验证码响应。
 *
 * @param mock        是否处于 Mock 模式（true 时验证码固定，便于演示）
 * @param mockCode    Mock 模式下直接回带验证码，省得去翻后端日志；
 *                    真实短信模式下该字段为 null
 * @param expireSeconds 验证码有效期
 */
public record SmsCodeResponse(boolean mock, String mockCode, int expireSeconds) {
}
