package com.blindcane.guardian.modules.device.dto;

import com.blindcane.guardian.modules.device.entity.Device;

import java.time.LocalDateTime;

/**
 * 设备状态视图。
 *
 * <p>首页卡片、设备详情页、被监护人列表内嵌都用同一个 VO —— 设备状态字段本来就
 * 只有这几个，拆成三个 VO 只会带来无意义的映射代码。
 *
 * @param online       是否在线
 * @param offlineSeconds 距最后一次上报已过去多少秒，App 可用它显示「3 分钟前」
 * @param firmwareVersion 固件版本（二期查看用，顺带回传）
 */
public record DeviceVO(Long id, String deviceSn, String name, Long wardId,
                       Integer battery, Integer signalLevel, Boolean online,
                       LocalDateTime lastOnlineAt, Long offlineSeconds,
                       String firmwareVersion) {

    public static DeviceVO from(Device device) {
        if (device == null) {
            return null;
        }
        Long offlineSeconds = device.getLastOnlineAt() == null
                ? null
                : java.time.Duration.between(device.getLastOnlineAt(), LocalDateTime.now()).getSeconds();
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
                device.getFirmwareVersion());
    }
}
