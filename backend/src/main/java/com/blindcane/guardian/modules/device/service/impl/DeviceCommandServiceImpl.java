package com.blindcane.guardian.modules.device.service.impl;

import com.blindcane.guardian.common.exception.BizException;
import com.blindcane.guardian.common.result.ErrorCode;
import com.blindcane.guardian.framework.websocket.WsMessageSender;
import com.blindcane.guardian.modules.device.dto.DeviceCommandAckRequest;
import com.blindcane.guardian.modules.device.dto.DeviceCommandMessage;
import com.blindcane.guardian.modules.device.dto.DeviceStatusMessage;
import com.blindcane.guardian.modules.device.dto.DeviceVO;
import com.blindcane.guardian.modules.device.entity.CaneCommand;
import com.blindcane.guardian.modules.device.entity.Device;
import com.blindcane.guardian.modules.device.mapper.DeviceMapper;
import com.blindcane.guardian.modules.device.service.DeviceCommandService;
import com.blindcane.guardian.modules.device.service.DeviceService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 命令下行实现。
 *
 * <p>整个类只做一件有难度的事：<b>把「状态变更」严格推迟到回执之后</b>。
 * 见 {@link #issue} 与 {@link #ack} 的注释。
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class DeviceCommandServiceImpl implements DeviceCommandService {

    private final DeviceMapper deviceMapper;
    private final DeviceService deviceService;
    private final WsMessageSender wsMessageSender;

    @Override
    @Transactional(rollbackFor = Exception.class)
    public DeviceCommandMessage issue(Long userId, Long deviceId, String rawCommand) {
        CaneCommand command = CaneCommand.parse(rawCommand);
        if (command == null) {
            throw BizException.of(ErrorCode.DEVICE_COMMAND_UNSUPPORTED,
                    "不支持的命令 " + rawCommand + "，当前支持：" + CaneCommand.supportedCodes()
                            + "（预留命令需固件实现后再开放）");
        }
        Device device = deviceService.requireAccessibleDevice(userId, deviceId);

        // 关键：这里只广播、**绝不写库**。
        // 手杖是不是真的静音了，取决于「某台与它相连的手机能不能把这一字节写进
        // RX 特征」—— 而那一步后端看不见。若在这里就翻转 mute_mode，
        // 一次写失败就会让云端与手杖永久失步（界面显示已静音，手杖还在响）。
        int currentMute = muteOf(device);
        Integer expectedMute = command.togglesMuteMode() ? flip(currentMute) : null;
        DeviceCommandMessage message = new DeviceCommandMessage(
                command.code(), command.label(), device.getWardId(), deviceId,
                expectedMute, System.currentTimeMillis());
        wsMessageSender.sendCommand(device.getWardId(), message);

        log.info("BLE 命令已下发: deviceId={}, command={}({}), 当前模式={}, 预期模式={}, 操作人={}（等待回执提交）",
                deviceId, command.code(), command.label(), currentMute, expectedMute, userId);
        return message;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public DeviceVO ack(Long userId, Long deviceId, DeviceCommandAckRequest request) {
        CaneCommand command = CaneCommand.parse(request.command());
        if (command == null) {
            throw BizException.of(ErrorCode.DEVICE_COMMAND_UNSUPPORTED,
                    "不支持的命令 " + request.command() + "，当前支持：" + CaneCommand.supportedCodes());
        }
        Device device = deviceService.requireAccessibleDevice(userId, deviceId);

        if (request.success() && command.togglesMuteMode()) {
            // 回执成功 = 字节确实写进 RX 特征 = 手杖固件已执行取反。
            // 这里重新按「库里当前值」取反，而不是采信下发时算出的预期值：
            // 连点两次按钮会产生两个在途命令，采信预期值会把两次切换算成一次
            int next = flip(muteOf(device));
            Device patch = new Device();
            patch.setId(deviceId);
            patch.setMuteMode(next);
            deviceMapper.updateById(patch);
            device.setMuteMode(next);
            log.info("BLE 命令执行成功并提交: deviceId={}, command={}, mute_mode -> {}",
                    deviceId, command.code(), next);
        } else if (request.success()) {
            log.info("BLE 命令执行成功（无状态变更）: deviceId={}, command={}", deviceId, command.code());
        } else {
            // 失败不改状态，但下面照样广播一次权威状态：
            // 客户端可能已经按「预期值」做了乐观显示，需要被纠正回来
            log.warn("BLE 命令执行失败，状态保持不变: deviceId={}, command={}, 原因={}",
                    deviceId, command.code(), request.detail());
        }

        wsMessageSender.sendDeviceStatus(device.getWardId(), DeviceStatusMessage.from(device));
        return DeviceVO.from(device);
    }

    private int muteOf(Device device) {
        return device.getMuteMode() == null ? Device.MUTE_OFF : device.getMuteMode();
    }

    private int flip(int muteMode) {
        return muteMode == Device.MUTE_ON ? Device.MUTE_OFF : Device.MUTE_ON;
    }
}
