package com.blindcane.guardian.modules.simulator;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.blindcane.guardian.framework.config.BlindcaneProperties;
import com.blindcane.guardian.modules.device.entity.Device;
import com.blindcane.guardian.modules.device.mapper.DeviceMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;
import java.util.Locale;

/**
 * 演示设备注册：应用启动时确保存在一台可被绑定的导盲杖。
 *
 * <p>幂等实现（已存在则跳过），因此重复启动不会产生多台演示设备。
 * 真实硬件接入后，设备档案应由设备出厂/激活流程写入，这里整块删掉即可。
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnProperty(name = "blindcane.simulator.enabled", havingValue = "true", matchIfMissing = true)
public class DeviceSimulatorBootstrap implements ApplicationRunner {

    private final DeviceMapper deviceMapper;
    private final BlindcaneProperties properties;

    @Override
    public void run(ApplicationArguments args) {
        BlindcaneProperties.Simulator sim = properties.getSimulator();
        String sn = sim.getDemoDeviceSn();
        String demoBleAddress = sim.getDemoBleAddress();

        Device existing = deviceMapper.selectOne(Wrappers.<Device>lambdaQuery().eq(Device::getDeviceSn, sn));
        if (existing != null) {
            // 补齐 BLE 字段：旧库里的演示设备是 V2 迁移之前注册的，没有蓝牙地址。
            // 没有地址就跑不了 Mock 扫描列表，所以这里顺手补登一次（幂等）
            if (existing.getBleAddress() == null && demoBleAddress != null && !demoBleAddress.isBlank()) {
                Device patch = new Device();
                patch.setId(existing.getId());
                patch.setBleAddress(demoBleAddress.toUpperCase(Locale.ROOT));
                deviceMapper.updateById(patch);
                log.info("已为演示设备补登虚拟蓝牙地址: sn={}, bleAddress={}", sn, demoBleAddress);
            } else {
                log.info("演示设备已存在，跳过注册: sn={}, deviceId={}, 绑定状态={}",
                        sn, existing.getId(),
                        existing.getWardId() == null ? "未绑定" : "已绑定 wardId=" + existing.getWardId());
            }
            return;
        }

        Device device = new Device();
        device.setDeviceSn(sn);
        device.setName(sim.getDemoDeviceName());
        device.setBattery(sim.getInitialBattery());
        device.setSignalLevel(4);
        device.setOnline(Device.ONLINE);
        device.setLastOnlineAt(LocalDateTime.now());
        device.setFirmwareVersion(sim.getDemoFirmware());
        device.setOfflineNotified(Device.OFFLINE_NOTIFIED_NO);
        if (demoBleAddress != null && !demoBleAddress.isBlank()) {
            device.setBleAddress(demoBleAddress.toUpperCase(Locale.ROOT));
        }
        // BLE 运行态显式给初值，避免 NULL 让「首帧判定已连接」那条分支走偏
        device.setMuteMode(Device.MUTE_OFF);
        device.setBleConnected(Device.BLE_DISCONNECTED);
        deviceMapper.insert(device);

        log.info("演示设备注册成功: sn={}, 初始电量={}%, bleAddress={}, deviceId={}",
                sn, sim.getInitialBattery(), device.getBleAddress(), device.getId());
    }
}
