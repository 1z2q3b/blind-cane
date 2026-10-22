package com.blindcane.guardian.modules.device.dto;

import java.time.LocalDateTime;

/**
 * 设备上报的统一载荷。
 *
 * <p>接入 BLE 之前，上报只有「电量 + 信号」两项，{@code recordReport} 用的是
 * 四个散参数。BLE 遥测又额外带来 RSSI / 障碍状态 / 障碍距离三个字段，
 * 再往签名里加参数就成了七个位置参数的方法 —— 调用方极易写错顺序，
 * 且编译期完全看不出来。改成 record 之后，新增字段不会破坏已有调用点。
 *
 * <p>{@code battery} 刻意保持可空：当前原型硬件（ESP32-S3）**没有电量检测电路**，
 * 遥测报文里根本没有这一项（见《硬件配置说明》第 6 节）。若把它当成必填，
 * 真机上报会被整帧拒绝；当成 0 又会让家属端看到「电量 0%」的假告警。
 * 因此约定：{@code null} = 本帧未携带电量，保持库中原值不变。
 *
 * @param deviceId          设备主键
 * @param battery           电量百分比，null = 本帧未携带
 * @param signalLevel       信号档位 1-4，null = 本帧未携带
 * @param bleRssi           BLE 链路原始 RSSI（dBm），null = 非 BLE 来源
 * @param obstacleStatus    障碍状态名（CLEAR/NEAR/DANGER），null = 本帧无遥测
 * @param obstacleDistanceCm 障碍距离（cm），null = 本帧无遥测
 * @param reportedAt        上报时间；null 时由服务端取当前时间
 */
public record DeviceReport(Long deviceId,
                           Integer battery,
                           Integer signalLevel,
                           Integer bleRssi,
                           String obstacleStatus,
                           Integer obstacleDistanceCm,
                           LocalDateTime reportedAt) {

    /**
     * 旧的四参数形态（S3 位置上报、S4 电量衰减、Mock 维护接口仍在用）。
     *
     * @deprecated 新代码请直接用 record 构造器并显式传 null；
     *             保留此工厂只为不改动已通过验证的存量调用点
     */
    @Deprecated
    public static DeviceReport of(Long deviceId, Integer battery, Integer signalLevel,
                                  LocalDateTime reportedAt) {
        return new DeviceReport(deviceId, battery, signalLevel, null, null, null, reportedAt);
    }

    /**
     * 本帧是否携带障碍遥测。
     *
     * <p>用于决定要不要刷新 {@code obstacle_reported_at}：只有真正带了遥测的帧
     * 才应推进这个「链路活性」时间戳，否则一次纯位置上报就会把
     * 「障碍数据几秒前」刷新成「刚刚」，抹掉数据过期的提示。
     */
    public boolean hasObstacleInfo() {
        return obstacleStatus != null || obstacleDistanceCm != null;
    }
}
