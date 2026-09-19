package com.blindcane.guardian.modules.device.service;

import com.blindcane.guardian.framework.config.BlindcaneProperties;
import com.blindcane.guardian.framework.redis.RedisGuard;
import com.blindcane.guardian.modules.alert.dto.AlertCreateCommand;
import com.blindcane.guardian.modules.alert.entity.AlertType;
import com.blindcane.guardian.modules.alert.service.AlertService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;

/**
 * 低电量告警的阶梯去重守卫。
 *
 * <p>为什么要去重：电量低于 20% 后设备仍在持续上报，若每次都告警，
 * 家属会被同一条「电量低」反复轰炸。策略是按 10% 分档，
 * 每跌进一个新的档位才告警一次（20% → 10% → 0%），共最多 2~3 次。
 *
 * <p>为什么用 Redis Set 而不是数据库字段：去重状态生命周期短、无需持久化，
 * 且充电恢复后要整体清空，Set + 自然过期比加表更省事。
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class BatteryAlertGuard {

    private static final String KEY_PREFIX = "alert:battery:notified:";
    /** 去重集合的保留时间：一周足够覆盖任何一次充电周期。 */
    private static final Duration RETENTION = Duration.ofDays(7);

    private final StringRedisTemplate redisTemplate;
    private final RedisGuard redisGuard;
    private final BlindcaneProperties properties;
    private final AlertService alertService;

    /**
     * 电量变化时调用。
     *
     * @param deviceId    设备
     * @param wardId      归属被监护人
     * @param battery     最新电量
     */
    public void onBatteryChanged(Long deviceId, Long wardId, Integer battery) {
        if (deviceId == null || wardId == null || battery == null) {
            return;
        }
        BlindcaneProperties.Device deviceProps = properties.getDevice();
        String key = KEY_PREFIX + deviceId;

        // 电量回升到阈值以上（充电中）：清空已通知档位，
        // 这样下次放电跌破 20% 还能重新提醒一次
        if (battery > deviceProps.getLowBatteryThreshold()) {
            redisGuard.run(() -> redisTemplate.delete(key));
            return;
        }

        int step = Math.max(1, deviceProps.getLowBatteryStep());
        // 档位向下取整：19% → 10 档，9% → 0 档
        int bucket = (battery / step) * step;
        Long added = redisGuard.call(() -> {
            Long n = redisTemplate.opsForSet().add(key, String.valueOf(bucket));
            redisTemplate.expire(key, RETENTION);
            return n;
        }, () -> null);

        // added == null 表示 Redis 不可用、去重失效：此时宁可多报一条也不漏报低电量
        if (added == null || added > 0) {
            log.info("低电量告警触发: deviceId={}, battery={}%, 档位={}", deviceId, battery, bucket);
            alertService.create(AlertCreateCommand
                    .simple(wardId, deviceId, AlertType.LOW_BATTERY)
                    .withNote("设备电量已降至 " + battery + "%，请提醒家人及时充电"));
        } else {
            log.debug("低电量事件已在本档位告警过，跳过: deviceId={}, battery={}%, 档位={}",
                    deviceId, battery, bucket);
        }
    }

    /** 解绑设备时清空去重状态，避免重绑后第一次低电量被吞掉。 */
    public void reset(Long deviceId) {
        redisGuard.run(() -> redisTemplate.delete(KEY_PREFIX + deviceId));
    }
}
