package com.blindcane.guardian.modules.device.task;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.blindcane.guardian.framework.config.BlindcaneProperties;
import com.blindcane.guardian.framework.websocket.WsMessageSender;
import com.blindcane.guardian.modules.alert.dto.AlertCreateCommand;
import com.blindcane.guardian.modules.alert.entity.AlertType;
import com.blindcane.guardian.modules.alert.service.AlertService;
import com.blindcane.guardian.modules.device.dto.DeviceStatusMessage;
import com.blindcane.guardian.modules.device.entity.Device;
import com.blindcane.guardian.modules.device.mapper.DeviceMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 设备离线检测（提示词 4.4）。
 *
 * <p>扫描周期与阈值都走配置，方便演示时临时调小（例如 1 分钟 + 5 秒）：
 * <pre>./build.sh spring-boot:run -Dspring-boot.run.arguments="--blindcane.device.offline-threshold-minutes=1 --blindcane.device.offline-scan-interval-ms=5000"</pre>
 *
 * <p>去抖：靠 device.offline_notified 标记。同一离线周期只发一次告警，
 * 设备恢复上报（DeviceService.recordReport）时会把标记复位。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class DeviceOfflineDetectTask {

    private final DeviceMapper deviceMapper;
    private final AlertService alertService;
    private final BlindcaneProperties properties;
    private final WsMessageSender wsMessageSender;

    @Scheduled(fixedDelayString = "${blindcane.device.offline-scan-interval-ms:60000}",
            initialDelayString = "${blindcane.device.offline-scan-interval-ms:60000}")
    public void detectOfflineDevices() {
        int thresholdMinutes = properties.getDevice().getOfflineThresholdMinutes();
        LocalDateTime deadline = LocalDateTime.now().minusMinutes(thresholdMinutes);

        // 判据刻意用「最后上报时间超时 + 本周期未告警过」，而不是「online = 1」：
        //  - 真实场景：设备停止上报，服务端 online 字段还停留在 1，靠超时发现；
        //  - 演示场景：Mock 会直接把 online 置 0（家属端立刻显示离线），
        //    若不看超时就会永远等不到告警。
        // 两种场景用同一个判据即可覆盖，去抖交给 offline_notified。
        //
        // isNotNull(lastOnlineAt) 很关键：从未上报过的新设备不应被判为离线。
        List<Device> lostDevices = deviceMapper.selectList(Wrappers.<Device>lambdaQuery()
                .isNotNull(Device::getWardId)
                .isNotNull(Device::getLastOnlineAt)
                .lt(Device::getLastOnlineAt, deadline)
                .eq(Device::getOfflineNotified, Device.OFFLINE_NOTIFIED_NO));
        if (lostDevices.isEmpty()) {
            return;
        }

        for (Device device : lostDevices) {
            Device patch = new Device();
            patch.setId(device.getId());
            patch.setOnline(Device.OFFLINE);
            patch.setSignalLevel(0);
            patch.setOfflineNotified(Device.OFFLINE_NOTIFIED_YES);
            // 设备都掉线了，手机与它之间不可能还保持着蓝牙链路。
            // 不置位的话，广播出去的载荷会同时带
            // online=false 与 bleConnected=true，家属端将显示「离线但蓝牙已连接」
            patch.setBleConnected(Device.BLE_DISCONNECTED);
            patch.setBleConnectedAt(LocalDateTime.now());
            deviceMapper.updateById(patch);
            device.setOnline(Device.OFFLINE);
            device.setBleConnected(Device.BLE_DISCONNECTED);

            log.warn("设备离线告警: sn={}, wardId={}, 最后上报={}",
                    device.getDeviceSn(), device.getWardId(), device.getLastOnlineAt());
            alertService.create(AlertCreateCommand
                    .simple(device.getWardId(), device.getId(), AlertType.DEVICE_OFFLINE)
                    .withNote("导盲杖已超过 " + thresholdMinutes + " 分钟未上报数据"));

            // 同步推一次设备状态，让家属端首页徽章立刻从"在线"翻成"离线"。
            // 用 offline() 而不是手工拼字段：它会把 bleConnected 一并置 false，
            // 并把障碍字段保留为「断开前的最后读数」
            wsMessageSender.sendDeviceStatus(device.getWardId(),
                    DeviceStatusMessage.offline(device));
        }
    }
}
