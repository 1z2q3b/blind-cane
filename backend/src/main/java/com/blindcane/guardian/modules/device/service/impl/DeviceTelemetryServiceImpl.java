package com.blindcane.guardian.modules.device.service.impl;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.blindcane.guardian.common.exception.BizException;
import com.blindcane.guardian.common.result.ErrorCode;
import com.blindcane.guardian.framework.config.BlindcaneProperties;
import com.blindcane.guardian.framework.websocket.WsMessageSender;
import com.blindcane.guardian.modules.device.dto.BleLinkRequest;
import com.blindcane.guardian.modules.device.dto.DeviceReport;
import com.blindcane.guardian.modules.device.dto.DeviceStatusMessage;
import com.blindcane.guardian.modules.device.dto.DeviceTelemetryRequest;
import com.blindcane.guardian.modules.device.dto.DeviceVO;
import com.blindcane.guardian.modules.device.dto.TelemetryAck;
import com.blindcane.guardian.modules.device.entity.Device;
import com.blindcane.guardian.modules.device.entity.ObstacleStatus;
import com.blindcane.guardian.modules.device.mapper.DeviceMapper;
import com.blindcane.guardian.modules.device.service.DeviceService;
import com.blindcane.guardian.modules.device.service.DeviceTelemetryService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.Objects;

/**
 * BLE 遥测上行通道实现。
 *
 * <p>这个类承担了接入 BLE 之后最关键的一处职责转变：
 * <b>上报源从「设备直连云端」变成了「手机网关转发」</b>。
 * 由此带来两个必须在这里解决的问题 ——
 * <ol>
 *   <li><b>频率失控</b>：手杖 500ms 一帧，是旧设计（10 秒一次位置上报）的 20 倍。
 *       若不节流，一台手杖就是 2 次 HTTP + 2 次 UPDATE/秒。
 *       这里用「状态变化才立刻放行 + 否则按窗口节流」的做法，
 *       既保证危险状态零延迟可见，又把稳态写入压到 1 次/秒以内。</li>
 *   <li><b>数据新鲜度</b>：障碍状态是「蓝牙连着时才有」的数据。断开后必须让
 *       {@code bleConnected=false}，否则过期的 DANGER 会一直挂在屏幕上误导家属。</li>
 * </ol>
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class DeviceTelemetryServiceImpl implements DeviceTelemetryService {

    private final DeviceMapper deviceMapper;
    private final DeviceService deviceService;
    private final BlindcaneProperties properties;
    private final WsMessageSender wsMessageSender;

    @Override
    @Transactional(rollbackFor = Exception.class)
    public TelemetryAck reportTelemetry(Long userId, Long deviceId, DeviceTelemetryRequest request) {
        Device device = deviceService.requireAccessibleDevice(userId, deviceId);
        BlindcaneProperties.Device deviceProps = properties.getDevice();

        Integer distanceCm = request.distanceCm();
        ObstacleStatus byDistance = ObstacleStatus.fromDistance(distanceCm,
                deviceProps.getObstacleNearCm(), deviceProps.getObstacleDangerCm());
        ObstacleStatus byHardware = ObstacleStatus.parse(request.status());
        // 距离优先于硬件状态：两者本来可以互相校验，报文自相矛盾时以距离为准。
        // 只有报文没带距离（固件省略了第二字段）时才退回采信状态串
        ObstacleStatus effective = byDistance != null ? byDistance : byHardware;
        if (effective == null) {
            throw BizException.of(ErrorCode.DEVICE_TELEMETRY_INVALID,
                    "上报报文缺少可用信息: status=" + request.status() + ", distanceCm=" + distanceCm);
        }

        // ---------- 节流 ----------
        // 放行条件（满足其一）：
        //   1) 障碍状态发生变化 —— 危险状态必须零延迟可见，不能被节流耽误；
        //   2) 距上次落库已超过窗口 —— 相当于心跳，同时维持「设备在线」的判定；
        //   3) 设备当前不在线 —— 恢复上报要立刻翻转在线状态并复位离线去抖标记。
        LocalDateTime now = LocalDateTime.now();
        long elapsedMs = device.getLastOnlineAt() == null
                ? Long.MAX_VALUE
                : Duration.between(device.getLastOnlineAt(), now).toMillis();
        boolean statusChanged = !Objects.equals(effective.name(), device.getObstacleStatus());
        int minIntervalMs = Math.max(0, deviceProps.getTelemetryMinIntervalMs());
        if (elapsedMs < minIntervalMs && !statusChanged && device.getOnline() != null
                && device.getOnline() == Device.ONLINE) {
            // 丢弃要打 debug 而不是 info：稳态下这个分支每秒都在发生，打 info 会淹掉日志
            log.debug("遥测节流丢弃: deviceId={}, status={} 未变化且距上次落库仅 {}ms",
                    deviceId, effective.name(), elapsedMs);
            return TelemetryAck.dropped(device, "状态未变化且距上次落库不足 " + minIntervalMs + "ms");
        }

        Integer signalLevel = signalLevelOf(request.rssi());
        // 走统一上报入口：在线状态、离线去抖复位、低电量阶梯、STOMP 推送都在那里，
        // 这里只负责把 BLE 特有的字段拼进同一份载荷
        deviceService.recordReport(new DeviceReport(deviceId, request.battery(), signalLevel,
                request.rssi(), effective.name(), distanceCm, now));

        // 能收到遥测本身就证明蓝牙链路是通的 —— 顺手把链路标记置位，
        // 免得 App 忘记单独上报一次 ble-link。仅在状态翻转时才写库，不增加稳态开销
        if (!device.isBleLinkUp()) {
            Device linkPatch = new Device();
            linkPatch.setId(deviceId);
            linkPatch.setBleConnected(Device.BLE_CONNECTED);
            linkPatch.setBleConnectedAt(now);
            deviceMapper.updateById(linkPatch);
            device.setBleConnected(Device.BLE_CONNECTED);
            device.setBleConnectedAt(now);
            log.info("蓝牙链路经遥测确认已连接: deviceId={}", deviceId);
        }

        return new TelemetryAck(true, null, effective.name(), distanceCm,
                device.getMuteMode() == null ? Device.MUTE_OFF : device.getMuteMode(),
                System.currentTimeMillis());
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public DeviceVO updateBleLink(Long userId, Long deviceId, BleLinkRequest request) {
        Device device = deviceService.requireAccessibleDevice(userId, deviceId);
        boolean connected = request.connected();
        boolean changed = device.isBleLinkUp() != connected;
        Integer rssi = connected ? request.rssi() : null;
        LocalDateTime now = LocalDateTime.now();
        LocalDateTime connectedAt = changed ? now : device.getBleConnectedAt();

        // 这里必须用 UpdateWrapper 而不是 updateById：**updateById 会跳过 null 字段**，
        // 断开时想把 ble_rssi 置空根本写不进去，结果库里留着一个 -57，
        // App 就会显示「蓝牙已断开，信号 -57dBm」这种自相矛盾的组合。
        // （同一个坑在 DeviceServiceImpl.unbind 里也踩过：置空必须显式 set null）
        final var update = Wrappers.<Device>lambdaUpdate()
                .eq(Device::getId, deviceId)
                .set(Device::getBleConnected,
                        connected ? Device.BLE_CONNECTED : Device.BLE_DISCONNECTED)
                .set(Device::getBleConnectedAt, connectedAt)
                .set(Device::getBleRssi, rssi);
        // 信号档位只在拿到 RSSI 时更新：signal_level 在 DDL 里是 NOT NULL，
        // 断开时显式 set null 会直接报「Column 'signal_level' cannot be null」。
        // 断连本身已由 ble_connected 表达，不需要把档位抹掉
        Integer level = signalLevelOf(rssi);
        if (level != null) {
            update.set(Device::getSignalLevel, level);
        }
        deviceMapper.update(null, update);

        // 同步内存实体后再广播，理由同 recordReport：省掉一次 SELECT
        device.setBleConnected(connected ? Device.BLE_CONNECTED : Device.BLE_DISCONNECTED);
        device.setBleConnectedAt(connectedAt);
        device.setBleRssi(rssi);
        if (level != null) {
            device.setSignalLevel(level);
        }

        if (changed) {
            log.info("蓝牙链路状态变化: deviceId={}, connected={}, rssi={}", deviceId, connected, rssi);
            // 断连也要广播：家属端必须立刻把障碍显示切换成「数据已过期」的形态，
            // 否则一个过期的 DANGER 会一直挂在屏幕上
            wsMessageSender.sendDeviceStatus(device.getWardId(), DeviceStatusMessage.from(device));
        }
        return DeviceVO.from(device);
    }

    /**
     * BLE RSSI（dBm）→ UI 信号档位 1-4。
     *
     * <p>档位边界取常见 BLE 经验值：-60dBm 以内是同房间的强信号，
     * -75 左右隔一道墙，-90 已接近断连边缘。
     * 之所以不直接把 dBm 给 App：旧版 UI 与历史数据都用 1-4 档，
     * 换口径会让所有历史记录的信号含义漂移；原始 dBm 存在 {@code ble_rssi} 里备查。
     *
     * @param rssi 链路 RSSI，null（App 未读取）时返回 null，表示「本次不更新信号档位」
     */
    private Integer signalLevelOf(Integer rssi) {
        if (rssi == null) {
            return null;
        }
        if (rssi >= -60) {
            return 4;
        }
        if (rssi >= -75) {
            return 3;
        }
        if (rssi >= -90) {
            return 2;
        }
        return 1;
    }
}
