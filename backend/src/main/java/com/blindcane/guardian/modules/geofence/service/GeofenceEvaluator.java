package com.blindcane.guardian.modules.geofence.service;

import com.blindcane.guardian.framework.redis.RedisGuard;
import com.blindcane.guardian.modules.alert.dto.AlertCreateCommand;
import com.blindcane.guardian.modules.alert.entity.AlertType;
import com.blindcane.guardian.modules.alert.service.AlertService;
import com.blindcane.guardian.modules.geofence.entity.Geofence;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 围栏命中判定。
 *
 * <p>挂在位置上报链路上，每次上报对每个启用围栏算一次距离。设计上要解决三个问题：
 *
 * <h3>1. 只在「跨越边界」时告警</h3>
 * 上报是 10 秒一次，如果按「现在在圈外」就告警，老人走出去之后会每 10 秒收到一条，
 * 家属很快就关掉通知了。所以记录每个围栏上一次的内外状态，只有状态翻转才产生告警。
 *
 * <h3>2. 首次上报只初始化、不告警</h3>
 * 服务重启 / 刚建围栏时状态是空的。这时如果按"当前在圈外"直接告警，
 * 会出现"刚配好围栏就立刻收到一条离开提醒"的假告警。所以状态缺失时静默写入基线。
 *
 * <h3>3. 边界抖动</h3>
 * GPS 精度 10~30 米，正好在半径上时来回跳，会产生大量进出告警。
 * 采用迟滞（hysteresis）：进入用 radius，离开要超过 radius + 15 米，
 * 中间这一段保持原状态不动。
 *
 * <h3>降级</h3>
 * 状态优先存 Redis（多实例共享）；Redis 不可用时退化为本机内存 Map，
 * 单实例演示场景下行为完全一致，不会因为缓存故障就丢失围栏告警能力。
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class GeofenceEvaluator {

    /** 上次内外状态：geofence:state:{fenceId} -> IN / OUT。 */
    private static final String KEY_STATE = "geofence:state:";
    /** 同一条围栏的最小告警间隔，防止极端抖动绕过迟滞。 */
    private static final String KEY_ALERT_LOCK = "geofence:alert:";

    /** 迟滞宽度（米）：离开判定要比半径多出这一段距离才算真的出去了。 */
    private static final double HYSTERESIS_M = 15.0;
    /** 状态保留 30 天，足够覆盖长期不动的围栏，又不会永久占内存。 */
    private static final Duration STATE_TTL = Duration.ofDays(30);
    /** 同一围栏 5 分钟内最多产生一条围栏告警。 */
    private static final Duration ALERT_INTERVAL = Duration.ofMinutes(5);

    private static final String STATE_IN = "IN";
    private static final String STATE_OUT = "OUT";
    private static final double EARTH_RADIUS_M = 6_371_000.0;

    private final GeofenceService geofenceService;
    private final AlertService alertService;
    private final StringRedisTemplate redisTemplate;
    private final RedisGuard redisGuard;

    /** Redis 不可用时的本机兜底状态，避免缓存故障直接吃掉围栏告警。 */
    private final Map<Long, String> localStates = new ConcurrentHashMap<>();

    /**
     * 判定一次上报位置，必要时产生围栏告警。
     *
     * <p>异常一律吞掉并记 warn：围栏判定是位置链路的**旁路增强**，
     * 它挂了不能导致位置上报失败——那样家属连"老人在哪"都看不到，损失更大。
     */
    public void evaluate(Long wardId, Long deviceId, double lng, double lat) {
        if (wardId == null) {
            return;
        }
        try {
            List<Geofence> fences = geofenceService.listEnabledByWard(wardId);
            if (fences.isEmpty()) {
                return;
            }
            for (Geofence fence : fences) {
                evaluateOne(fence, wardId, deviceId, lng, lat);
            }
        } catch (Exception e) {
            log.warn("围栏判定异常（已忽略，不影响位置上报）: wardId={}, lng={}, lat={}, err={}",
                    wardId, lng, lat, e.toString());
        }
    }

    private void evaluateOne(Geofence fence, Long wardId, Long deviceId, double lng, double lat) {
        double distance = distanceMeters(lat, lng, fence.getCenterLat(), fence.getCenterLng());
        int radius = fence.getRadiusM() == null ? 0 : fence.getRadiusM();

        String prev = readState(fence.getId());
        String current = decide(prev, distance, radius);

        if (current == null) {
            // 落在迟滞区内：维持原状态，什么都不做
            return;
        }
        if (current.equals(prev)) {
            // 状态没变，更新一次 TTL 即可（不写也无所谓，这里省掉一次写）
            return;
        }

        writeState(fence.getId(), current);
        if (prev == null) {
            log.info("围栏状态基线已建立: fenceId={}, name={}, state={}, 距中心 {}m",
                    fence.getId(), fence.getName(), current, Math.round(distance));
            return;
        }

        AlertType alertType = resolveAlertType(fence, current);
        if (alertType == null) {
            return;
        }
        if (!acquireAlertLock(fence.getId())) {
            log.debug("围栏告警在最小间隔内，已抑制: fenceId={}", fence.getId());
            return;
        }

        String note = buildNote(fence, current, distance, radius);
        alertService.create(AlertCreateCommand
                .withLocation(wardId, deviceId, alertType, lng, lat, null)
                .withNote(note));
        log.info("围栏命中: fenceId={}, type={}, 告警={}, 距离 {}m / 半径 {}m",
                fence.getId(), fence.getFenceType(), alertType, Math.round(distance), radius);
    }

    /**
     * 根据上一状态与当前位置算出当前状态。
     *
     * @return IN / OUT；返回 null 表示落在迟滞带里，应维持原状态
     */
    private String decide(String prev, double distance, int radius) {
        if (distance <= radius) {
            return STATE_IN;
        }
        if (distance >= radius + HYSTERESIS_M) {
            return STATE_OUT;
        }
        // 圆外但还在迟滞带内：只有确定曾经在外面才继续判为 OUT
        return STATE_OUT.equals(prev) ? STATE_OUT : null;
    }

    /**
     * 围栏类型决定触发方向：
     * 安全区关心"出去了"（EXIT），危险区关心"进来了"（ENTER）。
     * 反方向的变化只更新状态，不告警。
     */
    private AlertType resolveAlertType(Geofence fence, String current) {
        Integer type = fence.getFenceType();
        if (type != null && type == Geofence.TYPE_SAFE) {
            return STATE_OUT.equals(current) ? AlertType.GEOFENCE_EXIT : null;
        }
        if (type != null && type == Geofence.TYPE_DANGER) {
            return STATE_IN.equals(current) ? AlertType.GEOFENCE_ENTER : null;
        }
        return null;
    }

    private String buildNote(Geofence fence, String current, double distance, int radius) {
        String action = STATE_OUT.equals(current) ? "离开" : "进入";
        return String.format(Locale.ROOT,
                "%s「%s」：当前距中心 %.0f 米，围栏半径 %d 米",
                action, fence.getName(), distance, radius);
    }

    /**
     * 清除某个围栏的判定状态与告警抑制锁。
     *
     * <p>围栏被删除（或档案被删除带走围栏）时必须调用：否则状态会一直挂在 Redis 里，
     * 而 MySQL 的自增 id 在极端情况下（表被重建）可能复用，新围栏会带着旧状态开始判定，
     * 表现为"刚建好的围栏第一次上报就误报"。
     */
    public void clearState(Long fenceId) {
        localStates.remove(fenceId);
        if (!redisGuard.available()) {
            return;
        }
        redisGuard.run(() -> {
            redisTemplate.delete(KEY_STATE + fenceId);
            redisTemplate.delete(KEY_ALERT_LOCK + fenceId);
        });
    }

    // ------------------------------------------------------------------
    // 状态读写（Redis 优先，本机内存兜底）
    // ------------------------------------------------------------------

    private String readState(Long fenceId) {
        if (!redisGuard.available()) {
            return localStates.get(fenceId);
        }
        return redisGuard.call(
                () -> redisTemplate.opsForValue().get(KEY_STATE + fenceId),
                () -> localStates.get(fenceId));
    }

    private void writeState(Long fenceId, String state) {
        localStates.put(fenceId, state);
        if (!redisGuard.available()) {
            return;
        }
        redisGuard.run(() -> redisTemplate.opsForValue()
                .set(KEY_STATE + fenceId, state, STATE_TTL));
    }

    /** 抢占最小告警间隔；返回 true 表示本次可以发告警。 */
    private boolean acquireAlertLock(Long fenceId) {
        if (!redisGuard.available()) {
            // 没有 Redis 时不做间隔抑制，靠状态翻转本身挡住绝大部分重复
            return true;
        }
        Boolean acquired = redisGuard.call(() -> redisTemplate.opsForValue()
                .setIfAbsent(KEY_ALERT_LOCK + fenceId, "1", ALERT_INTERVAL), () -> true);
        return Boolean.TRUE.equals(acquired);
    }

    // ------------------------------------------------------------------
    // 距离计算
    // ------------------------------------------------------------------

    /**
     * 球面距离（haversine，米）。
     *
     * <p>为什么不用平面近似：城市尺度下 lng 的 1 度对应的实际米数随纬度变化
     * （郑州约 89 km/度，海南约 103 km/度），直接按固定系数算会在高纬度地区
     * 把围栏判定得偏大。haversine 公式只有几次三角函数，成本可以忽略。
     */
    static double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        return 2 * EARTH_RADIUS_M * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }
}
