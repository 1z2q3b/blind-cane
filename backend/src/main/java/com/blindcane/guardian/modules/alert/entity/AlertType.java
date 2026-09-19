package com.blindcane.guardian.modules.alert.entity;

import lombok.Getter;

/**
 * 告警类型与默认严重级别。
 *
 * <p>severity 直接写在枚举上，避免调用方每次创建告警时都要记得传：
 * 1 高（SOS / 跌倒，App 需全屏强提醒）· 2 中（离线 / 离开围栏）· 3 低（低电量 / 进入围栏）
 */
@Getter
public enum AlertType {

    /** 一键求助。 */
    SOS(1),
    /** 跌倒（含疑似升级）。 */
    FALL_DETECTED(1),
    /** 设备离线。 */
    DEVICE_OFFLINE(2),
    /** 低电量。 */
    LOW_BATTERY(3),
    /** 离开安全区。 */
    GEOFENCE_EXIT(2),
    /** 进入危险区。 */
    GEOFENCE_ENTER(3),
    ;

    private final int severity;

    AlertType(int severity) {
        this.severity = severity;
    }
}
