package com.blindcane.guardian.framework.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.TaskScheduler;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;

/**
 * 定时任务调度器。
 *
 * <p>为什么要显式声明一个名为 {@code taskScheduler} 的 Bean：
 * 应用里存在多个 TaskScheduler（WebSocket 心跳用了一个），
 * Spring 的 {@code ScheduledAnnotationBeanPostProcessor} 在无法唯一确定时会退回到
 * 自己新建一个单线程调度器 —— 结果就是「位置落库」这种会阻塞在数据库上的任务，
 * 把「离线检测」和「设备模拟器」全部堵在一个线程里排队。
 *
 * <p>显式给出名字后，所有 {@code @Scheduled} 方法都会用这个 4 线程池。
 */
@Configuration
@EnableScheduling
public class SchedulingConfig {

    @Bean
    public TaskScheduler taskScheduler() {
        ThreadPoolTaskScheduler scheduler = new ThreadPoolTaskScheduler();
        scheduler.setThreadNamePrefix("sched-");
        scheduler.setPoolSize(6);
        // 设为守护线程，避免开发时 Ctrl+C 后进程残留
        scheduler.setDaemon(true);
        scheduler.setWaitForTasksToCompleteOnShutdown(true);
        scheduler.setAwaitTerminationSeconds(10);
        return scheduler;
    }
}
