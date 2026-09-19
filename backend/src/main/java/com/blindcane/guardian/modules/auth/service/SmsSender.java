package com.blindcane.guardian.modules.auth.service;

/**
 * 短信发送抽象（可插拔）。
 *
 * <p>当前只提供 Mock 实现：{@code blindcane.sms.enabled=false} 时验证码固定 123456
 * 并打印日志，保证无第三方密钥也能跑通登录闭环（提示词 9.1）。
 *
 * <p>接入真实短信的方式：新增一个实现类并标注
 * {@code @ConditionalOnProperty(name = "blindcane.sms.enabled", havingValue = "true")}，
 * 例如封装腾讯云 SMS SDK。注意此时必须同时把 Mock 实现的条件设为 enabled=false，
 * 两者互斥，否则会出现两个 SmsSender Bean 导致注入失败。
 */
public interface SmsSender {

    /**
     * 发送登录验证码。实现方不应抛出异常打断登录主流程之外的调用方，
     * 但允许抛 BizException 表示发送失败（例如运营商限流）。
     */
    void sendCode(String phone, String code);

    /** 是否为 Mock 实现。Mock 时接口会把验证码回带，方便演示。 */
    boolean isMock();
}
