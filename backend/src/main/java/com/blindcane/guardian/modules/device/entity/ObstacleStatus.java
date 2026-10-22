package com.blindcane.guardian.modules.device.entity;

import java.util.Locale;

/**
 * 前方障碍状态（《BLE 对接规格 v1》第 3 节）。
 *
 * <p>这三个值与手杖固件上行报文里的第一个字段一一对应，
 * 但服务端并不无条件采信它 —— 见 {@link #fromDistance}。
 *
 * <p>{@code severity} 的意义在于给「谁更严重」一个可比较的次序：
 * 家属端的颜色、告警等级、以及「距离优先于状态」的取舍都依赖它。
 */
public enum ObstacleStatus {

    /** 畅通：距离 ≥ 100cm，蜂鸣器静音。 */
    CLEAR(0, "畅通"),

    /** 有障碍：20cm ≤ 距离 &lt; 100cm，蜂鸣器断续鸣叫。 */
    NEAR(1, "有障碍"),

    /** 危险：距离 &lt; 20cm，蜂鸣器急促短鸣。 */
    DANGER(2, "危险");

    private final int severity;
    private final String label;

    ObstacleStatus(int severity, String label) {
        this.severity = severity;
        this.label = label;
    }

    public int severity() {
        return severity;
    }

    /** 中文标签，供日志与 App 兜底展示。 */
    public String label() {
        return label;
    }

    public boolean isAtLeast(ObstacleStatus other) {
        return other != null && this.severity >= other.severity;
    }

    /**
     * 解析固件状态串（大小写不敏感，两侧空白容忍）。
     *
     * @return 无法识别时返回 {@code null} —— 刻意不抛异常：
     *         固件升级新增档位时，服务端应当降级到「按距离判定」而不是整帧失败
     */
    public static ObstacleStatus parse(String raw) {
        if (raw == null || raw.isBlank()) {
            return null;
        }
        String normalized = raw.trim().toUpperCase(Locale.ROOT);
        for (ObstacleStatus status : values()) {
            if (status.name().equals(normalized)) {
                return status;
            }
        }
        return null;
    }

    /**
     * 按距离推导状态，阈值来自配置（默认 20 / 100 cm）。
     *
     * <p>之所以让服务端再算一遍而不是直接用固件给的状态串：
     * 固件的分档逻辑写在设备端、刷机才能改，一旦线上发现阈值不合适，
     * 只能整批召回。放到服务端算，调配置即可生效，且能与固件状态互相校验。
     * 报文自相矛盾时以距离为准（见 DeviceTelemetryServiceImpl）。
     *
     * @param distanceCm 距离；{@code null} 表示本帧未携带距离
     * @return 无距离时返回 {@code null}，由调用方退回固件状态串
     */
    public static ObstacleStatus fromDistance(Integer distanceCm, int nearCm, int dangerCm) {
        if (distanceCm == null) {
            return null;
        }
        if (distanceCm < dangerCm) {
            return DANGER;
        }
        if (distanceCm < nearCm) {
            return NEAR;
        }
        return CLEAR;
    }
}
