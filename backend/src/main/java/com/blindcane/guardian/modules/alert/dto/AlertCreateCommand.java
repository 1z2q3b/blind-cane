package com.blindcane.guardian.modules.alert.dto;

import com.blindcane.guardian.modules.alert.entity.AlertType;

/**
 * 创建告警的入参。
 *
 * @param wardId         被监护人
 * @param deviceId       设备（可空）
 * @param type           告警类型，severity 默认由类型推导
 * @param severity       严重级别覆盖值（可空）。只有「疑似跌倒」这类需要先低压告警、
 *                       超时再升级的场景才会传：创建时给 2（警示），升级时改成 1（紧急）。
 *                       为 null 时用 {@link AlertType#getSeverity()} 的默认值。
 * @param lng            告警经度（可空，低电量/离线类告警没有精确位置）
 * @param lat            告警纬度（可空）
 * @param address        逆地理文案（可空）
 * @param note           备注
 * @param pendingConfirm 是否「疑似待确认」（跌倒用，超时未确认则升级）
 */
public record AlertCreateCommand(Long wardId, Long deviceId, AlertType type,
                                 Integer severity,
                                 Double lng, Double lat, String address,
                                 String note, boolean pendingConfirm) {

    /** 最简形态：只有归属和类型，位置留空（由调用方后续补）。 */
    public static AlertCreateCommand simple(Long wardId, Long deviceId, AlertType type) {
        return new AlertCreateCommand(wardId, deviceId, type, null,
                null, null, null, null, false);
    }

    public static AlertCreateCommand withLocation(Long wardId, Long deviceId, AlertType type,
                                                  Double lng, Double lat, String address) {
        return new AlertCreateCommand(wardId, deviceId, type, null,
                lng, lat, address, null, false);
    }

    public AlertCreateCommand withNote(String note) {
        return new AlertCreateCommand(wardId, deviceId, type, severity,
                lng, lat, address, note, pendingConfirm);
    }

    public AlertCreateCommand withSeverity(Integer newSeverity) {
        return new AlertCreateCommand(wardId, deviceId, type, newSeverity,
                lng, lat, address, note, pendingConfirm);
    }

    public AlertCreateCommand asPendingConfirm() {
        return new AlertCreateCommand(wardId, deviceId, type, severity,
                lng, lat, address, note, true);
    }
}
