package com.blindcane.guardian.modules.device.dto;

/**
 * 下发到手杖的命令（STOMP {@code /topic/ward/{wardId}/command} 的载荷）。
 *
 * <p>为什么命令要绕一圈走 WebSocket 而不是后端直连蓝牙：
 * 后端起在服务器上，没有蓝牙射频。真正持有 BLE 链路的是某一位家属的手机，
 * 所以后端只能把命令「广播」到 ward 主题，由那台连着狗杖的手机订阅后
 * 写入 RX 特征。这也意味着：如果当时没有任何手机与手杖保持连接，
 * 命令就没人执行 —— 这一点必须让家属端可见（页面上提示「手杖未连接」），
 * 否则按钮点下去毫无反应，会以为是软件坏了。
 *
 * @param command   命令码，如 {@code M}
 * @param commandName 命令中文名，直接取 {@code CaneCommand.label()}，
 *                    避免 App 再维护一份码值 → 文案的映射表
 * @param wardId    被监护人（订阅主题用）
 * @param deviceId  目标设备
 * @param muteMode  执行成功后期望的静音模式。它是「预期值」而非「已生效值」——
 *                  真正提交状态要等 {@code /command/ack} 回执。
 *                  App 可以用它做乐观显示，但必须在收到权威状态后覆盖
 * @param issuedAt  下发时刻（毫秒），供 App 丢弃过期的重放命令
 */
public record DeviceCommandMessage(String command,
                                   String commandName,
                                   Long wardId,
                                   Long deviceId,
                                   Integer muteMode,
                                   long issuedAt) {
}
