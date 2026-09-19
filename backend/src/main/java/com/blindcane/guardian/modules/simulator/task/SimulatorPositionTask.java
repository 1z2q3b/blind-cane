package com.blindcane.guardian.modules.simulator.task;

import com.blindcane.guardian.framework.config.BlindcaneProperties;
import com.blindcane.guardian.modules.location.service.LocationService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.concurrent.ThreadLocalRandom;

/**
 * 设备模拟器 · 位置漂移（提示词 6.6）。
 *
 * <p>MVP 阶段没有真实硬件，靠这个任务按固定周期走一次随机游走，
 * 产生一条真实的位置上报 —— 走的是「设备 → 后端」完全相同的链路
 * （{@link LocationService#reportByDeviceSn}），所以 Redis 热数据、STOMP 推送、
 * 批量落库三个下游全部会被真实驱动，而不是造假数据塞进数据库。
 *
 * <p>实现要点：
 * <ul>
 *   <li>步长按米给（{@code stepMeters}），再换算成经纬度。纬度 1° ≈ 111_320 m；
 *       经度 1° ≈ 111_320·cos(lat)，越靠近两极经度方向越「密」，必须按纬度修正，
 *       否则在高纬度地区步长会肉眼可见地缩水。</li>
 *   <li>加了一个「回拉半径」：随机游走长期看是发散的，演示半小时就会飘到几公里外，
 *       地图上看着莫名其妙。超过半径就往原点方向偏置，让轨迹始终在学校附近打转。</li>
 *   <li>概率上偶尔「静止」几步，让轨迹看起来像人走走停停，而不是匀速机器。</li>
 * </ul>
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class SimulatorPositionTask {

    /** 纬度每度对应的米数（WGS-84 椭球平均值，做模拟足够）。 */
    private static final double METERS_PER_DEGREE_LAT = 111_320d;

    private final LocationService locationService;
    private final BlindcaneProperties properties;

    /** 演示设备 SN：默认取配置，可被 spring.bean 覆盖以便演示多台设备。 */
    @Value("${blindcane.simulator.demo-device-sn:BC-2024-DEMO01}")
    private String demoDeviceSn;

    /** 当前模拟坐标，首次调用时用配置里的起点初始化。 */
    private volatile double currentLng = Double.NaN;
    private volatile double currentLat = Double.NaN;

    @Scheduled(fixedDelayString = "${blindcane.simulator.report-interval-ms:10000}",
            initialDelayString = "${blindcane.simulator.report-interval-ms:10000}")
    public void drift() {
        BlindcaneProperties.Simulator sim = properties.getSimulator();
        if (!sim.isEnabled() || !sim.isPositionDriftEnabled()) {
            return;
        }
        initIfNeeded(sim);

        double step = sim.getStepMeters();
        ThreadLocalRandom random = ThreadLocalRandom.current();

        // 约 25% 概率原地不动，模拟路口等待 / 停顿
        boolean still = random.nextInt(100) < 25;
        double rad = random.nextDouble(0, Math.PI * 2);

        double dLat = still ? 0 : Math.cos(rad) * step / METERS_PER_DEGREE_LAT;
        double dLng = still ? 0
                : Math.sin(rad) * step / (METERS_PER_DEGREE_LAT * Math.cos(Math.toRadians(currentLat)));

        double nextLat = currentLat + dLat;
        double nextLng = currentLng + dLng;

        // 回拉：超出半径就朝原点方向强行拉回一步，避免无限发散
        double pullRadiusMeters = step * 120;
        double[] pulled = pullBack(nextLng, nextLat, sim, pullRadiusMeters, step);
        nextLng = pulled[0];
        nextLat = pulled[1];

        currentLng = nextLng;
        currentLat = nextLat;

        // 精度/速度给一点随机抖动，让 App 端 UI 不至于像在读死数据
        double accuracy = 5 + random.nextDouble(0, 10);
        double speed = still ? 0.0 : 0.6 + random.nextDouble(0, 0.9);

        locationService.reportByDeviceSn(demoDeviceSn, round6(nextLng), round6(nextLat),
                round2(accuracy), round2(speed));
        log.debug("【模拟器】位置漂移 sn={}, lng={}, lat={}, 静止={}", demoDeviceSn, nextLng, nextLat, still);
    }

    private void initIfNeeded(BlindcaneProperties.Simulator sim) {
        if (Double.isNaN(currentLng) || Double.isNaN(currentLat)) {
            synchronized (this) {
                if (Double.isNaN(currentLng) || Double.isNaN(currentLat)) {
                    currentLng = sim.getOriginLng();
                    currentLat = sim.getOriginLat();
                    log.info("【模拟器】位置漂移起点初始化: lng={}, lat={}", currentLng, currentLat);
                }
            }
        }
    }

    /** 若超出回拉半径，则把坐标往原点方向拉回一步。 */
    private double[] pullBack(double lng, double lat, BlindcaneProperties.Simulator sim,
                              double pullRadiusMeters, double stepMeters) {
        double dLatM = (lat - sim.getOriginLat()) * METERS_PER_DEGREE_LAT;
        double dLngM = (lng - sim.getOriginLng())
                * METERS_PER_DEGREE_LAT * Math.cos(Math.toRadians(lat));
        double distance = Math.hypot(dLatM, dLngM);
        if (distance <= pullRadiusMeters) {
            return new double[]{lng, lat};
        }
        // 单位方向向量 * 步长，从原点往外推 stepMeters，即把点拉回边界内侧
        double ratio = stepMeters / distance;
        return new double[]{
                sim.getOriginLng() + (lng - sim.getOriginLng()) * (1 - ratio),
                sim.getOriginLat() + (lat - sim.getOriginLat()) * (1 - ratio)
        };
    }

    private double round6(double v) {
        return Math.round(v * 1_000_000d) / 1_000_000d;
    }

    private double round2(double v) {
        return Math.round(v * 100d) / 100d;
    }
}
