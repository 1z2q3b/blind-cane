package com.blindcane.guardian.modules.simulator.task;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.blindcane.guardian.framework.config.BlindcaneProperties;
import com.blindcane.guardian.modules.device.entity.Device;
import com.blindcane.guardian.modules.device.mapper.DeviceMapper;
import com.blindcane.guardian.modules.device.service.DeviceService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 设备模拟器 · 电量衰减（提示词 6.6）。
 *
 * <p>每小时整点把已绑定设备的电量 -1%，走到 20% 以下会自然触发
 * {@code BatteryAlertGuard} 的阶梯告警，因此「低电量告警」这条链路
 * 不需要单独造假数据，靠时间推移就能在演示中真实触发。
 *
 * <p>刻意走 {@link DeviceService#recordReport} 而不是直接 update：
 * 这样才会经过在线状态刷新、离线去抖复位、低电量阶梯判断、设备状态推送
 * 这一整套真实副作用。若图省事直接写库，会出现「电量掉了但家属端首页没变」
 * 这种前后不一致的问题。
 *
 * <p>演示技巧：把 cron 临时改成每 10 秒一次即可快速看到电量下降与告警。
 * <pre>--blindcane.simulator.battery-decay-cron="0/10 * * * * *"</pre>
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class SimulatorBatteryTask {

    /** 电量下限：不降到 0，避免演示时设备直接"关机"导致后续步骤全断。 */
    private static final int MIN_BATTERY = 1;

    private final DeviceMapper deviceMapper;
    private final DeviceService deviceService;
    private final BlindcaneProperties properties;

    @Scheduled(cron = "${blindcane.simulator.battery-decay-cron:0 0 * * * *}")
    public void decay() {
        if (!properties.getSimulator().isEnabled()) {
            return;
        }
        // 只衰减已绑定设备：未绑定的设备没有 wardId，衰减了也没有家属能看到
        List<Device> devices = deviceMapper.selectList(Wrappers.<Device>lambdaQuery()
                .isNotNull(Device::getWardId));
        if (devices.isEmpty()) {
            return;
        }

        LocalDateTime now = LocalDateTime.now();
        for (Device device : devices) {
            int current = device.getBattery() == null
                    ? properties.getSimulator().getInitialBattery()
                    : device.getBattery();
            int next = Math.max(MIN_BATTERY, current - 1);
            if (next == current) {
                continue;
            }
            // 信号强度沿用当前值：电量衰减不代表信号变化，传 null 会被 recordReport 覆盖成空
            deviceService.recordReport(device.getId(), next, device.getSignalLevel(), now);
            log.info("【模拟器】电量衰减 sn={}: {}% -> {}%", device.getDeviceSn(), current, next);
        }
    }
}
