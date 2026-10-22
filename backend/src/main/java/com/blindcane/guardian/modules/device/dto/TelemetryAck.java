package com.blindcane.guardian.modules.device.dto;

import com.blindcane.guardian.modules.device.entity.Device;

/**
 * 遥测上报的回执。
 *
 * <p>回执不只是「收到了」，它还是 App 侧自适应降频的依据：
 * 手杖 500ms 一帧，而服务端的节流窗口是 1 秒，所以稳态下大约每 2 帧
 * 就会有 1 帧被丢弃。若 App 不知道被丢，它会继续按 2 次/秒发请求。
 * 拿到 {@code accepted=false} 后，App 就能把这一帧视为「云端已有相同状态」，
 * 据此压低转发频率，而不是盲目重试。
 *
 * <p>无论采纳与否都回带当前权威状态（{@code obstacleStatus} / {@code distanceCm} /
 * {@code muteMode}）：被丢弃的帧同样需要让 App 校正本地显示，
 * 否则 App 的乐观更新会与云端长期偏离。
 *
 * @param accepted      本帧是否被采纳落库
 * @param reason        被丢弃的原因（accepted=true 时为 null）
 * @param obstacleStatus 云端当前权威障碍状态
 * @param distanceCm    云端当前权威障碍距离
 * @param muteMode      云端当前权威静音模式（0 工作 / 1 静音）
 * @param serverTimeMs  服务端时刻，供 App 校时与计算往返延迟
 */
public record TelemetryAck(boolean accepted,
                           String reason,
                           String obstacleStatus,
                           Integer distanceCm,
                           Integer muteMode,
                           long serverTimeMs) {

    /** 被采纳：状态已落库。 */
    public static TelemetryAck accepted(Device device) {
        return new TelemetryAck(true, null,
                device.getObstacleStatus(), device.getObstacleDistanceCm(),
                device.getMuteMode(), System.currentTimeMillis());
    }

    /** 被节流丢弃：状态未变且距上次落库不足窗口。 */
    public static TelemetryAck dropped(Device device, String reason) {
        return new TelemetryAck(false, reason,
                device.getObstacleStatus(), device.getObstacleDistanceCm(),
                device.getMuteMode(), System.currentTimeMillis());
    }
}
