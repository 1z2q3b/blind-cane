package com.blindcane.guardian.modules.device.service.impl;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.blindcane.guardian.common.exception.BizException;
import com.blindcane.guardian.common.result.ErrorCode;
import com.blindcane.guardian.framework.websocket.WsMessageSender;
import com.blindcane.guardian.modules.device.dto.DeviceBindRequest;
import com.blindcane.guardian.modules.device.dto.DeviceStatusMessage;
import com.blindcane.guardian.modules.device.dto.DeviceVO;
import com.blindcane.guardian.modules.device.entity.Device;
import com.blindcane.guardian.modules.device.mapper.DeviceMapper;
import com.blindcane.guardian.modules.device.service.BatteryAlertGuard;
import com.blindcane.guardian.modules.device.service.DeviceService;
import com.blindcane.guardian.modules.location.service.LocationCacheService;
import com.blindcane.guardian.modules.ward.entity.Ward;
import com.blindcane.guardian.modules.ward.mapper.WardMapper;
import com.blindcane.guardian.modules.ward.service.GuardianService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;

@Slf4j
@Service
@RequiredArgsConstructor
public class DeviceServiceImpl implements DeviceService {

    private final DeviceMapper deviceMapper;
    private final WardMapper wardMapper;
    private final GuardianService guardianService;
    private final BatteryAlertGuard batteryAlertGuard;
    private final LocationCacheService locationCacheService;
    private final WsMessageSender wsMessageSender;

    @Override
    @Transactional(rollbackFor = Exception.class)
    public DeviceVO bind(Long userId, DeviceBindRequest request) {
        // 先确认调用者确实是该被监护人的监护人，再动设备
        guardianService.requireGuardian(userId, request.wardId());
        Ward ward = wardMapper.selectById(request.wardId());
        if (ward == null) {
            throw BizException.of(ErrorCode.WARD_NOT_FOUND);
        }

        Device device = deviceMapper.selectOne(Wrappers.<Device>lambdaQuery()
                .eq(Device::getDeviceSn, request.deviceSn()));
        if (device == null) {
            throw BizException.of(ErrorCode.DEVICE_SN_NOT_FOUND,
                    "设备序列号 " + request.deviceSn() + " 不存在，请核对杖体背面的标签");
        }
        if (device.getWardId() != null) {
            throw BizException.of(ErrorCode.DEVICE_ALREADY_BOUND);
        }
        // device.ward_id 是单值，一个被监护人只能拥有一台设备；
        // 要换设备必须先解绑，否则两台设备会争抢同一 ward 的归属
        Long occupied = deviceMapper.selectCount(Wrappers.<Device>lambdaQuery()
                .eq(Device::getWardId, request.wardId()));
        if (occupied != null && occupied > 0) {
            throw BizException.of(ErrorCode.DEVICE_WARD_OCCUPIED);
        }

        Device patch = new Device();
        patch.setId(device.getId());
        patch.setWardId(ward.getId());
        // 绑定即视为「计时起点」：把最后上报时间重置为此刻并清掉离线去抖标记。
        // 否则一台在仓库里放了很久、或刚从别的账号解绑的设备，
        // 一绑定就会因为历史时间戳陈旧而立刻弹出「设备离线」，属于误报。
        patch.setLastOnlineAt(LocalDateTime.now());
        patch.setOfflineNotified(Device.OFFLINE_NOTIFIED_NO);
        if (device.getName() == null || device.getName().isBlank()) {
            patch.setName(ward.getName() + "的导盲杖");
        }
        deviceMapper.updateById(patch);

        log.info("设备绑定成功: sn={}, deviceId={}, wardId={}, 操作人={}",
                device.getDeviceSn(), device.getId(), ward.getId(), userId);
        return DeviceVO.from(deviceMapper.selectById(device.getId()));
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void unbind(Long userId, Long deviceId) {
        Device device = requireAccessibleDevice(userId, deviceId);

        // 注意：MyBatis-Plus 的 updateById 默认跳过 null 字段，
        // 无法用它把 ward_id 置为 NULL，必须用 UpdateWrapper 显式 set null。
        deviceMapper.update(null, Wrappers.<Device>lambdaUpdate()
                .eq(Device::getId, deviceId)
                .set(Device::getWardId, null)
                .set(Device::getOnline, Device.OFFLINE)
                .set(Device::getOfflineNotified, Device.OFFLINE_NOTIFIED_NO));

        // 清理与这台设备绑定的临时状态，避免重绑后行为异常
        batteryAlertGuard.reset(deviceId);
        locationCacheService.evict(device.getWardId());
        log.info("设备解绑成功: deviceId={}, 原 wardId={}, 操作人={}", deviceId, device.getWardId(), userId);
    }

    @Override
    public DeviceVO status(Long userId, Long deviceId) {
        return DeviceVO.from(requireAccessibleDevice(userId, deviceId));
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void recordReport(Long deviceId, Integer battery, Integer signalLevel, LocalDateTime reportedAt) {
        Device device = deviceMapper.selectById(deviceId);
        if (device == null) {
            log.warn("收到未知设备的上报，已忽略: deviceId={}", deviceId);
            return;
        }
        LocalDateTime reportTime = reportedAt == null ? LocalDateTime.now() : reportedAt;

        Device patch = new Device();
        patch.setId(deviceId);
        patch.setOnline(Device.ONLINE);
        patch.setLastOnlineAt(reportTime);
        patch.setSignalLevel(signalLevel);
        patch.setBattery(battery);
        // 恢复上报即重置离线去抖标记：同一离线周期只告警一次的「周期」以此处为终点
        if (device.getOfflineNotified() != null
                && device.getOfflineNotified() == Device.OFFLINE_NOTIFIED_YES) {
            patch.setOfflineNotified(Device.OFFLINE_NOTIFIED_NO);
        }
        deviceMapper.updateById(patch);

        // 只有电量真的变化才走阶梯判断，避免每次位置上报都碰一次 Redis
        if (battery != null && !battery.equals(device.getBattery())) {
            batteryAlertGuard.onBatteryChanged(deviceId, device.getWardId(), battery);
        }
        // 设备状态推送放在最后：先保证数据落库，再通知前端刷新，
        // 避免家属端收到推送后立刻回查却拿到旧值
        wsMessageSender.sendDeviceStatus(device.getWardId(),
                new DeviceStatusMessage(true, battery, signalLevel));
    }

    @Override
    public Device requireAccessibleDevice(Long userId, Long deviceId) {
        Device device = deviceMapper.selectById(deviceId);
        if (device == null) {
            throw BizException.of(ErrorCode.DEVICE_NOT_FOUND);
        }
        if (device.getWardId() == null) {
            throw BizException.of(ErrorCode.DEVICE_NOT_BOUND);
        }
        guardianService.requireGuardian(userId, device.getWardId());
        return device;
    }
}
