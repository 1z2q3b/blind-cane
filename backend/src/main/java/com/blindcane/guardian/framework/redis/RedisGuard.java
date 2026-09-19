package com.blindcane.guardian.framework.redis;

import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataAccessException;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Supplier;

/**
 * Redis 访问熔断 / 降级门面。
 *
 * <p>为什么需要它：Redis 在架构里承担的都是「加速与去重」类职责
 * （最新位置缓存、验证码、JWT 黑名单、低电量去重），真正的最终数据源是 MySQL。
 * 因此 Redis 挂掉时业务应该降级，而不是抛异常 —— 但直接 try-catch 有两个副作用：
 * <ol>
 *   <li>位置上报 10 秒一次，Redis 一挂就每 10 秒打一条带全栈的 ERROR，日志被彻底淹没；</li>
 *   <li>每次失败都要等连接超时（本项目配的 3s），高频调用会把调度线程白白卡住。</li>
 * </ol>
 *
 * <p>这里用一个极简的「三态」开关解决：
 * <ul>
 *   <li>Closed（正常）：直接执行；</li>
 *   <li>Open（熔断）：失败后的 {@value #OPEN_SECONDS} 秒内直接走降级值，不再发起连接；</li>
 *   <li>Half-Open（探测）：冷却期满后放行一次请求，成功即闭合，失败则重新熔断。</li>
 * </ul>
 *
 * <p>日志策略：首次失败打一条带堆栈的 ERROR（保留排障线索），
 * 之后同一故障窗口内最多每 {@value #SILENT_MINUTES} 分钟一条无堆栈的 WARN，
 * Redis 恢复时打一条 INFO。
 */
@Slf4j
@Component
public class RedisGuard {

    private static final long OPEN_SECONDS = 30;
    private static final long SILENT_MINUTES = 5;

    private static final long OPEN_MILLIS = Duration.ofSeconds(OPEN_SECONDS).toMillis();
    private static final long SILENT_MILLIS = Duration.ofMinutes(SILENT_MINUTES).toMillis();

    private final AtomicBoolean open = new AtomicBoolean(false);
    /** 熔断到期时间：早于该时刻的请求全部走降级值，之后允许一次探测。 */
    private volatile long recoverAt = 0L;
    private volatile long lastWarnAt = 0L;

    /** Redis 当前是否可用；false 表示处于熔断窗口内。 */
    public boolean available() {
        return !open.get();
    }

    /**
     * 执行一次 Redis 操作，失败时返回降级值。
     *
     * @param action   真实操作
     * @param fallback 降级值（Redis 不可用时返回）
     */
    public <T> T call(Supplier<T> action, Supplier<T> fallback) {
        if (open.get() && System.currentTimeMillis() < recoverAt) {
            warnThrottled();
            return fallback.get();
        }
        try {
            T result = action.get();
            if (open.compareAndSet(true, false)) {
                log.info("Redis 已恢复连接，缓存相关功能恢复正常");
            }
            return result;
        } catch (DataAccessException e) {
            trip(e);
            return fallback.get();
        }
    }

    /** 无返回值的 Redis 操作，失败时静默降级。 */
    public void run(Runnable action) {
        call(() -> {
            action.run();
            return null;
        }, () -> null);
    }

    // ------------------------------------------------------------------

    private void trip(DataAccessException e) {
        // getAndSet 返回旧值：旧值为 false 说明是本次故障的第一次失败
        boolean firstFailure = !open.getAndSet(true);
        recoverAt = System.currentTimeMillis() + OPEN_MILLIS;
        if (firstFailure) {
            log.error("Redis 不可用，已降级（{} 秒内不再重试，MySQL 主链路不受影响）: {}",
                    OPEN_SECONDS, e.getMessage(), e);
        } else {
            warnThrottled();
        }
    }

    private void warnThrottled() {
        long now = System.currentTimeMillis();
        if (now - lastWarnAt > SILENT_MILLIS) {
            lastWarnAt = now;
            log.warn("Redis 仍不可用，缓存读写继续降级；恢复后会自动生效");
        }
    }
}
