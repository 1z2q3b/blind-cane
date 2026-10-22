package com.blindcane.guardian.modules.device.service.impl;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.blindcane.guardian.common.exception.BizException;
import com.blindcane.guardian.common.result.ErrorCode;
import com.blindcane.guardian.framework.websocket.WsMessageSender;
import com.blindcane.guardian.modules.device.dto.BleAddressRequest;
import com.blindcane.guardian.modules.device.dto.DeviceBindRequest;
import com.blindcane.guardian.modules.device.dto.DeviceReport;
import com.blindcane.guardian.modules.device.dto.DeviceStatusMessage;
import com.blindcane.guardian.modules.device.dto.DeviceVO;
import com.blindcane.guardian.modules.device.entity.Device;
import com.blindcane.guardian.modules.device.entity.ObstacleStatus;
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
import java.util.Locale;

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

        // 蓝牙地址冲突检测放在业务层而不是数据库唯一索引上：
        // iOS 的随机 UUID 会让「同一台手杖」在不同手机上得到不同地址，
        // 唯一约束反而会误伤正常绑定（见 V2 迁移的说明）
        String bleAddress = normalizeBleAddress(request.bleAddress());
        requireBleAddressAvailable(bleAddress, device.getId());

        Device patch = new Device();
        patch.setId(device.getId());
        patch.setWardId(ward.getId());
        // 绑定即视为「计时起点」：把最后上报时间重置为此刻并清掉离线去抖标记。
        // 否则一台在仓库里放了很久、或刚从别的账号解绑的设备，
        // 一绑定就会因为历史时间戳陈旧而立刻弹出「设备离线」，属于误报。
        patch.setLastOnlineAt(LocalDateTime.now());
        patch.setOfflineNotified(Device.OFFLINE_NOTIFIED_NO);
        if (bleAddress != null) {
            patch.setBleAddress(bleAddress);
        }
        if (request.name() != null && !request.name().isBlank()) {
            patch.setName(request.name().trim());
        } else if (device.getName() == null || device.getName().isBlank()) {
            patch.setName(ward.getName() + "的导盲杖");
        }
        deviceMapper.updateById(patch);

        log.info("设备绑定成功: sn={}, deviceId={}, wardId={}, bleAddress={}, 操作人={}",
                device.getDeviceSn(), device.getId(), ward.getId(), bleAddress, userId);
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

        // 清理与这台设备绑定的临时状态，避免重绑后行为异常：
        // 尤其是 BLE 运行态 —— 不清的话下一个使用者一绑定就会看到
        // 上一任留下的「危险 12cm」「已静音」，那是另一根手杖的状态
        clearBleState(deviceId);
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
    public DeviceVO bindBleAddress(Long userId, Long deviceId, BleAddressRequest request) {
        Device device = requireAccessibleDevice(userId, deviceId);
        String bleAddress = normalizeBleAddress(request.bleAddress());
        requireBleAddressAvailable(bleAddress, deviceId);

        Device patch = new Device();
        patch.setId(deviceId);
        patch.setBleAddress(bleAddress);
        deviceMapper.updateById(patch);

        log.info("手杖蓝牙地址已更新: deviceId={}, bleAddress={}, 操作人={}",
                deviceId, bleAddress, userId);
        return DeviceVO.from(deviceMapper.selectById(deviceId));
    }

    @Override
    public void clearBleState(Long deviceId) {
        if (deviceId == null) {
            return;
        }
        // 同样必须走 UpdateWrapper：这里要写的**全是 null**
        // （清除语义），updateById 会把它们整批跳过，等于什么都没做
        deviceMapper.update(null, Wrappers.<Device>lambdaUpdate()
                .eq(Device::getId, deviceId)
                .set(Device::getBleConnected, Device.BLE_DISCONNECTED)
                .set(Device::getBleConnectedAt, null)
                .set(Device::getBleRssi, null)
                .set(Device::getObstacleStatus, null)
                .set(Device::getObstacleDistanceCm, null)
                .set(Device::getObstacleReportedAt, null)
                .set(Device::getMuteMode, Device.MUTE_OFF));
        log.info("设备 BLE 运行时状态已清空: deviceId={}", deviceId);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void recordReport(DeviceReport report) {
        if (report == null || report.deviceId() == null) {
            return;
        }
        Long deviceId = report.deviceId();
        Device device = deviceMapper.selectById(deviceId);
        if (device == null) {
            log.warn("收到未知设备的上报，已忽略: deviceId={}", deviceId);
            return;
        }
        LocalDateTime reportTime = report.reportedAt() == null ? LocalDateTime.now() : report.reportedAt();
        Integer previousBattery = device.getBattery();
        String obstacleStatus = normalizeObstacleStatus(report.obstacleStatus());
        boolean touchObstacle = report.hasObstacleInfo();

        Device patch = new Device();
        patch.setId(deviceId);
        patch.setOnline(Device.ONLINE);
        patch.setLastOnlineAt(reportTime);
        patch.setSignalLevel(report.signalLevel());
        patch.setBattery(report.battery());
        patch.setBleRssi(report.bleRssi());
        patch.setObstacleStatus(obstacleStatus);
        patch.setObstacleDistanceCm(report.obstacleDistanceCm());
        // 只有携带遥测的帧才推进「链路活性」时间戳，否则一次纯位置上报
        // 会把「障碍数据 30 秒前」刷成「刚刚」，抹掉数据过期的提示
        if (touchObstacle) {
            patch.setObstacleReportedAt(reportTime);
        }
        // 恢复上报即重置离线去抖标记：同一离线周期只告警一次的「周期」以此处为终点
        if (device.getOfflineNotified() != null
                && device.getOfflineNotified() == Device.OFFLINE_NOTIFIED_YES) {
            patch.setOfflineNotified(Device.OFFLINE_NOTIFIED_NO);
        }
        deviceMapper.updateById(patch);

        // 同步内存实体后再广播，省掉一次 SELECT。
        // 注意只覆盖**本帧携带**的字段：BLE 报文没有电量，
        // 若在这里无条件 setBattery(null) 会把库里的历史电量也一起抹掉
        device.setOnline(Device.ONLINE);
        device.setLastOnlineAt(reportTime);
        if (report.signalLevel() != null) {
            device.setSignalLevel(report.signalLevel());
        }
        if (report.battery() != null) {
            device.setBattery(report.battery());
        }
        if (report.bleRssi() != null) {
            device.setBleRssi(report.bleRssi());
        }
        if (obstacleStatus != null) {
            device.setObstacleStatus(obstacleStatus);
        }
        if (report.obstacleDistanceCm() != null) {
            device.setObstacleDistanceCm(report.obstacleDistanceCm());
        }
        if (touchObstacle) {
            device.setObstacleReportedAt(reportTime);
        }

        // 只有电量真的变化才走阶梯判断，避免每次遥测都碰一次 Redis
        if (report.battery() != null && !report.battery().equals(previousBattery)) {
            batteryAlertGuard.onBatteryChanged(deviceId, device.getWardId(), report.battery());
        }
        // 设备状态推送放在最后：先保证数据落库，再通知前端刷新，
        // 避免家属端收到推送后立刻回查却拿到旧值
        wsMessageSender.sendDeviceStatus(device.getWardId(), DeviceStatusMessage.from(device));
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

    /** 统一大写并去空白：库里存的地址要么全大写，要么是 UUID 的规范大写形式。 */
    private String normalizeBleAddress(String raw) {
        if (raw == null || raw.isBlank()) {
            return null;
        }
        return raw.trim().toUpperCase(Locale.ROOT);
    }

    /** 把固件传来的状态串规范成枚举名；无法识别时返回 null（不阻断本帧电量/位置入库）。 */
    private String normalizeObstacleStatus(String rawStatus) {
        ObstacleStatus fromHardware = ObstacleStatus.parse(rawStatus);
        return fromHardware == null ? null : fromHardware.name();
    }

    /**
     * 地址占用检测（尽力而为）。
     *
     * <p>只拦「已绑定到别人」的情况：未绑定的设备之间地址相同无所谓，
     * 那多半是同一台还没归属的手杖被登记了两次。
     */
    private void requireBleAddressAvailable(String bleAddress, Long selfDeviceId) {
        if (bleAddress == null) {
            return;
        }
        Device conflict = deviceMapper.selectOne(Wrappers.<Device>lambdaQuery()
                .eq(Device::getBleAddress, bleAddress)
                .last("LIMIT 1"));
        if (conflict != null && !conflict.getId().equals(selfDeviceId)
                && conflict.getWardId() != null) {
            throw BizException.of(ErrorCode.DEVICE_BLE_ADDRESS_OCCUPIED,
                    "蓝牙地址 " + bleAddress + " 已绑定到其他被监护人（设备 "
                            + conflict.getDeviceSn() + "）");
        }
    }
}
