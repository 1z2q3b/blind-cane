package com.blindcane.guardian;

import org.apache.ibatis.annotations.Mapper;
import org.mybatis.spring.annotation.MapperScan;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * 智能导盲杖 · 家属监护端 后端服务启动类。
 *
 * <p>模块划分：auth（认证）/ user（家属与通知偏好）/ ward（被监护人与监护关系）/
 * device（设备与离线检测）/ location（位置双写）/ alert（告警产生与分发）/
 * push（推送抽象）/ simulator（设备模拟器，演示用）。
 */
@SpringBootApplication
@EnableScheduling  // 离线检测、设备模拟器位置漂移、电量衰减都依赖定时任务
@EnableAsync       // 告警分发、位置落库走异步，避免阻塞上报主链路
/*
 * 注意这里的 annotationClass 过滤，不能省：
 * 若只写 @MapperScan("com.blindcane.guardian.modules")，MyBatis 会把该包下
 * 「所有接口」都注册成 Mapper 代理 —— 包括 AuthService / SmsSender 这类业务接口。
 * 后果是注入时拿到的是 Mapper 代理而非真实实现，调用即抛
 * BindingException: Invalid bound statement (not found)。
 * 限定只扫描带 @Mapper 的接口后，业务接口不会再被误注册。
 */
@MapperScan(basePackages = "com.blindcane.guardian.modules", annotationClass = Mapper.class)
public class GuardianApplication {

    public static void main(String[] args) {
        SpringApplication.run(GuardianApplication.class, args);
    }
}
