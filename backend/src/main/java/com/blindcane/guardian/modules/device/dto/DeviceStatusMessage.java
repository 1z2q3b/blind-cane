package com.blindcane.guardian.modules.device.dto;

import com.blindcane.guardian.modules.device.entity.Device;
import com.blindcane.guardian.modules.device.entity.ObstacleStatus;

import java.time.LocalDateTime;

/**
 * 设备状态变化消息（STOMP {@code /topic/ward/{wardId}/device} 的载荷，对应提示词 7.3）。
 *
 * <p>刻意不带 deviceId / name / firmwareVersion 这类静态信息：
 * 家属端是按 ward 主题订阅的，本来就知道自己订阅的是谁；
 * 传整个 DeviceVO 等于每次状态抖动都把静态字段重发一遍。
 *
 * <p>BLE 接入后新增了障碍与链路字段。这里有一个必须守住的契约：
 * <b>{@code bleConnected=false} 时 {@code obstacleStatus} 虽然仍有值，
 * 但它代表的是「断开前的最后读数」，不是当前状态。</b>
 * 之所以仍然带上而不是置 null，是为了让 App 能显示
 * 「蓝牙已断开 · 最后状态：危险 12cm」—— 信息量比空白大，且不会误导。
 *
 * @param online       是否在线
 * @param battery      电量百分比（原型硬件无电量检测，可能为 null）
 * @param signalLevel  信号档位 1-4
 * @param bleConnected BLE 链路是否已连接
 * @param obstacleStatus 障碍状态 CLEAR/NEAR/DANGER
 * @param obstacleDistanceCm 障碍距离（cm）
 * @param muteMode     0 工作 / 1 静音
 * @param obstacleReportedAt 最近一次障碍遥测时间，供 App 判断读数新鲜度
 */
public record DeviceStatusMessage(Boolean online,
                                  Integer battery,
                                  Integer signalLevel,
                                  Boolean bleConnected,
                                  String obstacleStatus,
                                  Integer obstacleDistanceCm,
                                  Integer muteMode,
                                  LocalDateTime obstacleReportedAt) {

    /** 按设备当前内存状态构造。 */
    public static DeviceStatusMessage from(Device device) {
        if (device == null) {
            return null;
        }
        ObstacleStatus status = device.obstacleStatusEnum();
        return new DeviceStatusMessage(
                device.getOnline() != null && device.getOnline() == Device.ONLINE,
                device.getBattery(),
                device.getSignalLevel(),
                device.isBleLinkUp(),
                status == null ? null : status.name(),
                device.getObstacleDistanceCm(),
                device.getMuteMode(),
                device.getObstacleReportedAt());
    }

    /**
     * 离线形态：在线置 false、信号归 0、BLE 链路一并置 false。
     *
     * <p>为什么离线要顺手把 {@code bleConnected} 也置 false：设备都掉线了，
     * 手机与它之间不可能还保持着链路。若这条广播留着 {@code bleConnected=true}，
     * App 就会一边显示「设备离线」一边显示「蓝牙已连接」，自相矛盾。
     * 障碍字段则保留 —— 同 {@code from()}，它是「最后读数」而非当前状态。
     */
    public static DeviceStatusMessage offline(Device device) {
        DeviceStatusMessage online = from(device);
        if (online == null) {
            return null;
        }
        return new DeviceStatusMessage(false, device.getBattery(), 0, false,
                online.obstacleStatus(), online.obstacleDistanceCm(),
                online.muteMode(), online.obstacleReportedAt());
    }
}
