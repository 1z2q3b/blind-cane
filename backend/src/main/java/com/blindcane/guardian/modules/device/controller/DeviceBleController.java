package com.blindcane.guardian.modules.device.controller;

import com.blindcane.guardian.common.result.ApiResponse;
import com.blindcane.guardian.framework.security.CurrentUserHolder;
import com.blindcane.guardian.modules.device.dto.BleLinkRequest;
import com.blindcane.guardian.modules.device.dto.DeviceCommandAckRequest;
import com.blindcane.guardian.modules.device.dto.DeviceCommandMessage;
import com.blindcane.guardian.modules.device.dto.DeviceCommandRequest;
import com.blindcane.guardian.modules.device.dto.DeviceTelemetryRequest;
import com.blindcane.guardian.modules.device.dto.DeviceVO;
import com.blindcane.guardian.modules.device.dto.TelemetryAck;
import com.blindcane.guardian.modules.device.service.DeviceCommandService;
import com.blindcane.guardian.modules.device.service.DeviceTelemetryService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * BLE 通道接口：遥测上行 + 命令下行。
 *
 * <p>整体数据流（对应《BLE 对接规格 v1》）：
 * <pre>
 *   导盲杖 ──BLE Notify(6E400003)──▶ 手机 App ──POST /telemetry────────▶ 后端
 *   导盲杖 ◀──BLE Write(6E400002)── 手机 App ◀──STOMP /topic/.../command── 后端
 * </pre>
 *
 * <p>四个接口各自的存在理由：
 * <ul>
 *   <li>{@code /telemetry}：手杖 500ms 一帧的障碍遥测，由 App 节流后转发；</li>
 *   <li>{@code /ble-link}：链路连/断事件。必须显式上报，因为断连是立即发生的，
 *       靠遥测超时推断必然滞后，而滞后期内家属端会把过期的「危险」当成当前状态；</li>
 *   <li>{@code /command}：家属按钮 → 广播给家属端 → 与手杖连着的那台手机写 RX 特征；</li>
 *   <li>{@code /command/ack}：写特征的结果回执。<b>它是设备状态的唯一提交点</b> ——
 *       只有手机确认「字符确实写进 RX 特征」，云端才提交模式变更。</li>
 * </ul>
 *
 * <p>这些接口全部要求登录：上报者身份（当前登录家属）即鉴权依据 ——
 * 只有该被监护人的监护人才能代设备上报，避免任意账号伪造他人设备状态。
 */
@Tag(name = "设备 · BLE 通道", description = "遥测上行 / 蓝牙链路 / 命令下发与回执")
@RestController
@RequestMapping("/api/v1/devices")
@RequiredArgsConstructor
public class DeviceBleController {

    private final DeviceTelemetryService telemetryService;
    private final DeviceCommandService commandService;

    @Operation(summary = "上报障碍遥测（App 网关转发）",
            description = "对应 BLE 上行报文 `<状态>,<距离cm>`，由 App 解析后转成结构化 JSON。"
                    + "status 与 distanceCm 至少给一个；两者都给时以距离为准（可挡住固件笔误）。"
                    + "accepted=false 表示该帧被节流丢弃（状态未变且距上次落库不足窗口），"
                    + "App 可据此自适应降频。建议 App 侧策略：状态变化立即转发 + 30 秒一次心跳")
    @PostMapping("/{id}/telemetry")
    public ApiResponse<TelemetryAck> telemetry(@PathVariable("id") Long id,
                                               @Valid @RequestBody DeviceTelemetryRequest request) {
        return ApiResponse.success(telemetryService.reportTelemetry(
                CurrentUserHolder.requireUserId(), id, request));
    }

    @Operation(summary = "上报蓝牙链路状态",
            description = "连接成功 / 断开时各调一次。断开时后端会清掉 RSSI 并广播，"
                    + "让其他家属端把障碍显示切换到「数据已过期」形态")
    @PostMapping("/{id}/ble-link")
    public ApiResponse<DeviceVO> bleLink(@PathVariable("id") Long id,
                                         @Valid @RequestBody BleLinkRequest request) {
        return ApiResponse.success(telemetryService.updateBleLink(
                CurrentUserHolder.requireUserId(), id, request));
    }

    @Operation(summary = "下发命令到手杖",
            description = "目前支持 M（切换工作/静音）。后端不直接连蓝牙 —— "
                    + "它把命令广播到 /topic/ward/{wardId}/command，"
                    + "由与手杖连着的那台手机写入 RX 特征执行。"
                    + "本接口不改变设备状态，状态变更要等 /command/ack 回执。"
                    + "命令不在白名单返回 104007")
    @PostMapping("/{id}/command")
    public ApiResponse<DeviceCommandMessage> command(@PathVariable("id") Long id,
                                                     @Valid @RequestBody DeviceCommandRequest request) {
        return ApiResponse.success(commandService.issue(
                CurrentUserHolder.requireUserId(), id, request.command()));
    }

    @Operation(summary = "命令执行回执",
            description = "App 写完 RX 特征后回调。回执是状态的唯一提交点："
                    + "success=true 才提交静音模式变更并广播；"
                    + "success=false 时状态保持不变，但同样广播一次权威状态，"
                    + "用来纠正客户端在等待期间可能已做的乐观显示")
    @PostMapping("/{id}/command/ack")
    public ApiResponse<DeviceVO> commandAck(@PathVariable("id") Long id,
                                            @Valid @RequestBody DeviceCommandAckRequest request) {
        return ApiResponse.success(commandService.ack(
                CurrentUserHolder.requireUserId(), id, request));
    }
}
