package com.blindcane.guardian.modules.device.dto;

import com.blindcane.guardian.modules.device.entity.Device;
import com.blindcane.guardian.modules.device.entity.ObstacleStatus;

import java.time.Duration;
import java.time.LocalDateTime;

/**
 * 设备状态视图。
 *
 * <p>首页卡片、设备详情页、被监护人列表内嵌都用同一个 VO —— 设备状态字段本来就
 * 只有这几个，拆成三个 VO 只会带来无意义的映射代码。
 *
 * <p>BLE 接入后新增了两组字段，App 端必须按这个优先级渲染：
 * <ol>
 *   <li>{@code bleConnected=false} → 障碍相关字段一律展示为「数据已过期」，
 *       即使 {@code obstacleStatus} 有值也不要拿它下结论；</li>
 *   <li>{@code bleConnected=true} 时，{@code obstacleSeconds} 才是「几秒前的读数」，
 *       可用它做数据新鲜度提示。</li>
 * </ol>
 *
 * @param online       是否在线
 * @param offlineSeconds 距最后一次上报已过去多少秒，App 可用它显示「3 分钟前」
 * @param firmwareVersion 固件版本（二期查看用，顺带回传）
 * @param bleAddress   手杖蓝牙地址（Android=MAC / iOS=随机 UUID）
 * @param bleConnected BLE 链路是否已连接
 * @param bleConnectedAt 链路状态最近一次变化时间
 * @param bleRssi      BLE 链路原始 RSSI（dBm），UI 仍用 signalLevel 档位
 * @param obstacleStatus 障碍状态 CLEAR/NEAR/DANGER
 * @param obstacleDistanceCm 障碍距离（cm）
 * @param obstacleReportedAt 最近一次障碍遥测时间
 * @param obstacleSeconds 距最近一次障碍遥测过去多少秒（数据新鲜度）
 * @param muteMode     0 工作 / 1 静音
 */
public record DeviceVO(Long id, String deviceSn, String name, Long wardId,
                       Integer battery, Integer signalLevel, Boolean online,
                       LocalDateTime lastOnlineAt, Long offlineSeconds,
                       String firmwareVersion,
                       String bleAddress, Boolean bleConnected, LocalDateTime bleConnectedAt,
                       Integer bleRssi,
                       String obstacleStatus, Integer obstacleDistanceCm,
                       LocalDateTime obstacleReportedAt, Long obstacleSeconds,
                       Integer muteMode) {

    public static DeviceVO from(Device device) {
        if (device == null) {
            return null;
        }
        LocalDateTime now = LocalDateTime.now();
        Long offlineSeconds = device.getLastOnlineAt() == null
                ? null
                : Duration.between(device.getLastOnlineAt(), now).getSeconds();
        Long obstacleSeconds = device.getObstacleReportedAt() == null
                ? null
                : Duration.between(device.getObstacleReportedAt(), now).getSeconds();
        // 库里存的是字符串，出参统一规范成枚举名：万一有历史脏值（大小写不一），
        // 一次 parse 就能抹平，App 端可以直接 switch 无需容错
        ObstacleStatus obstacle = device.obstacleStatusEnum();
        return new DeviceVO(
                device.getId(),
                device.getDeviceSn(),
                device.getName(),
                device.getWardId(),
                device.getBattery(),
                device.getSignalLevel(),
                device.getOnline() != null && device.getOnline() == Device.ONLINE,
                device.getLastOnlineAt(),
                offlineSeconds,
                device.getFirmwareVersion(),
                device.getBleAddress(),
                device.isBleLinkUp(),
                device.getBleConnectedAt(),
                device.getBleRssi(),
                obstacle == null ? null : obstacle.name(),
                device.getObstacleDistanceCm(),
                device.getObstacleReportedAt(),
                obstacleSeconds,
                device.getMuteMode());
    }
}
