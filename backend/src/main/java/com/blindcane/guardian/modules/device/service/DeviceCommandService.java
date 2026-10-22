package com.blindcane.guardian.modules.device.service;

import com.blindcane.guardian.modules.device.dto.DeviceCommandAckRequest;
import com.blindcane.guardian.modules.device.dto.DeviceCommandMessage;
import com.blindcane.guardian.modules.device.dto.DeviceVO;

/**
 * 命令下行通道（家属端 → 云端 → 手机网关 → 手杖 BLE RX）。
 *
 * <p>分成 {@link #issue} 与 {@link #ack} 两步而不是一个同步方法，
 * 是因为链路上有一段后端管不到的部分 —— 手机写 BLE 特征。
 * 后端无法知道它何时成功、是否成功，所以必须把「下发」与「确认」
 * 拆成两个独立请求，用回执作为状态的唯一提交点。
 */
public interface DeviceCommandService {

    /**
     * 下发命令：校验白名单 → 广播到 {@code /topic/ward/{wardId}/command}。
     *
     * <p><b>不改变设备状态。</b>返回的消息里带的 {@code muteMode} 只是预期值。
     *
     * @throws com.blindcane.guardian.common.exception.BizException 104007（命令不在白名单）
     */
    DeviceCommandMessage issue(Long userId, Long deviceId, String rawCommand);

    /**
     * 命令回执：{@code success=true} 且命令会改模式时，才翻转 {@code mute_mode}。
     *
     * <p>无论成功失败都会广播一次权威设备状态。
     */
    DeviceVO ack(Long userId, Long deviceId, DeviceCommandAckRequest request);
}
