package com.blindcane.guardian.modules.simulator.controller;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.blindcane.guardian.common.exception.BizException;
import com.blindcane.guardian.common.result.ApiResponse;
import com.blindcane.guardian.common.result.ErrorCode;
import com.blindcane.guardian.framework.config.BlindcaneProperties;
import com.blindcane.guardian.modules.device.dto.BleLinkRequest;
import com.blindcane.guardian.modules.device.dto.DeviceCommandAckRequest;
import com.blindcane.guardian.modules.device.dto.DeviceTelemetryRequest;
import com.blindcane.guardian.modules.device.dto.DeviceVO;
import com.blindcane.guardian.modules.device.dto.TelemetryAck;
import com.blindcane.guardian.modules.device.entity.Device;
import com.blindcane.guardian.modules.device.mapper.DeviceMapper;
import com.blindcane.guardian.modules.device.service.DeviceCommandService;
import com.blindcane.guardian.modules.device.service.DeviceTelemetryService;
import com.blindcane.guardian.modules.ward.entity.Ward;
import com.blindcane.guardian.modules.ward.mapper.WardMapper;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Mock · BLE 模拟器（演示专用）。
 *
 * <p>存在的理由：这个项目的交付里，手杖有时在实验室、有时在答辩现场，
 * 而演示不能依赖「手杖恰好带着、电恰好够、手机恰好配对成功」。
 * 本控制器扮演的就是「那台连着蓝牙的手机」—— 它把所有由 App 发起的
 * HTTP 调用逐个暴露成可以手动触发的接口，于是即使一台真实手杖都没有，
 * 也能把完整的「绑定 → 连接 → 遥测 → 命令 → 回执」链路跑一遍。
 *
 * <p>关键：它走的**不是**旁路。所有接口最终都调用真实的
 * {@link DeviceTelemetryService} 与 {@link DeviceCommandService}，
 * 因此节流窗口、距离优先、回执提交这些规则在这里同样生效 ——
 * 用它验证过的行为，换成真机也是一样的（唯一差别是 App 在中间多做了一次
 * 「解析 NUS 文本 → 转 JSON」）。
 *
 * <p>仅在 {@code blindcane.simulator.enabled=true} 时注册（生产 profile 下不存在）。
 */
@Slf4j
@Tag(name = "Mock · BLE 模拟器",
        description = "演示专用：无蓝牙硬件时扮演手机网关，驱动真实遥测与命令链路")
@RestController
@RequestMapping("/api/v1/mock/ble")
@RequiredArgsConstructor
@ConditionalOnProperty(name = "blindcane.simulator.enabled", havingValue = "true", matchIfMissing = true)
public class MockBleController {

    private final DeviceMapper deviceMapper;
    private final WardMapper wardMapper;
    private final DeviceTelemetryService telemetryService;
    private final DeviceCommandService commandService;
    private final BlindcaneProperties properties;

    @Operation(summary = "模拟 BLE 扫描",
            description = "按广播名 StarPath 过滤出的设备列表。字段与 App 端 ScanResult 对齐："
                    + "name / bleAddress / rssi / bound / deviceId / deviceSn")
    @GetMapping("/scan")
    public ApiResponse<List<Map<String, Object>>> scan() {
        BlindcaneProperties.Simulator sim = properties.getSimulator();
        List<Device> devices = deviceMapper.selectList(
                Wrappers.<Device>lambdaQuery().isNotNull(Device::getBleAddress));
        String fallbackAddress = sim.getDemoBleAddress();

        // 一台已登记蓝牙地址的设备都没有时，退化成一个「幽灵广播」：
        // 否则刚部署完、还没绑定任何设备的环境里，扫描页会是一片空白，
        // 看起来像功能坏了。这条记录不带 deviceId，App 会引导用户走绑定流程
        if (devices.isEmpty() && fallbackAddress != null && !fallbackAddress.isBlank()) {
            Map<String, Object> ghost = new LinkedHashMap<>();
            ghost.put("name", "StarPath");
            ghost.put("bleAddress", fallbackAddress.toUpperCase(Locale.ROOT));
            ghost.put("rssi", -58);
            ghost.put("bound", false);
            ghost.put("deviceId", null);
            ghost.put("deviceSn", sim.getDemoDeviceSn());
            ghost.put("registered", false);
            return ApiResponse.success(List.of(ghost));
        }

        List<Map<String, Object>> result = devices.stream().map(device -> {
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("name", "StarPath");
            item.put("bleAddress", device.getBleAddress());
            item.put("rssi", device.getBleRssi() == null ? -58 : device.getBleRssi());
            item.put("bound", device.getWardId() != null);
            item.put("deviceId", device.getId());
            item.put("deviceSn", device.getDeviceSn());
            item.put("registered", true);
            return item;
        }).toList();
        return ApiResponse.success(result);
    }

    @Operation(summary = "模拟连接手杖成功",
            description = "等价于 App 收到 STATE_CONNECTED 并完成服务发现与订阅 TX 通知。"
                    + "后端会置 bleConnected=true 并广播一次设备状态")
    @PostMapping("/devices/{sn}/connect")
    public ApiResponse<DeviceVO> connect(@PathVariable("sn") String sn,
                                         @RequestParam(value = "rssi", defaultValue = "-58") Integer rssi) {
        Device device = requireBoundDevice(sn);
        return ApiResponse.success(telemetryService.updateBleLink(
                primaryGuardianOf(device), device.getId(), new BleLinkRequest(true, rssi)));
    }

    @Operation(summary = "模拟蓝牙断开",
            description = "等价于 onConnectionStateChange 收到 STATE_DISCONNECTED。"
                    + "断开后障碍状态仍保留但 bleConnected=false，"
                    + "App 必须据此把显示切换成「数据已过期」形态")
    @PostMapping("/devices/{sn}/disconnect")
    public ApiResponse<DeviceVO> disconnect(@PathVariable("sn") String sn) {
        Device device = requireBoundDevice(sn);
        return ApiResponse.success(telemetryService.updateBleLink(
                primaryGuardianOf(device), device.getId(), new BleLinkRequest(false, null)));
    }

    @Operation(summary = "模拟上报一帧障碍遥测",
            description = "等价于 App 解析了 TX 特征的一行文本后转发。只传 distanceCm 即可，"
                    + "状态由后端按阈值推导（可验证「距离优先于状态」）。"
                    + "典型值：畅通 235 / 有障碍 80 / 危险 12")
    @PostMapping("/devices/{sn}/telemetry")
    public ApiResponse<TelemetryAck> telemetry(@PathVariable("sn") String sn,
                                               @RequestParam(value = "status", required = false) String status,
                                               @RequestParam(value = "distanceCm", required = false) Integer distanceCm,
                                               @RequestParam(value = "battery", required = false) Integer battery,
                                               @RequestParam(value = "rssi", required = false) Integer rssi) {
        Device device = requireBoundDevice(sn);
        return ApiResponse.success(telemetryService.reportTelemetry(
                primaryGuardianOf(device), device.getId(),
                new DeviceTelemetryRequest(status, distanceCm, battery, rssi, System.currentTimeMillis())));
    }

    @Operation(summary = "模拟连续上报 N 帧",
            description = "用于观察节流效果：同样内容连发 N 帧，只有满足「状态变化 / 超过窗口」"
                    + "的那几帧会 accepted=true，其余被丢弃。默认 6 帧 × 200ms")
    @PostMapping("/devices/{sn}/stream")
    public ApiResponse<List<TelemetryAck>> stream(@PathVariable("sn") String sn,
                                                  @RequestParam(value = "status", required = false) String status,
                                                  @RequestParam(value = "distanceCm", required = false) Integer distanceCm,
                                                  @RequestParam(value = "count", defaultValue = "6") Integer count,
                                                  @RequestParam(value = "intervalMs", defaultValue = "200") Integer intervalMs) {
        if (count == null || count < 1 || count > 40) {
            throw BizException.of(ErrorCode.PARAM_ERROR, "count 必须在 1-40 之间");
        }
        Device device = requireBoundDevice(sn);
        Long guardianId = primaryGuardianOf(device);

        List<TelemetryAck> acks = new ArrayList<>(count);
        for (int i = 0; i < count; i++) {
            acks.add(telemetryService.reportTelemetry(guardianId, device.getId(),
                    new DeviceTelemetryRequest(status, distanceCm, null, null, System.currentTimeMillis())));
            if (intervalMs != null && intervalMs > 0 && i < count - 1) {
                try {
                    Thread.sleep(intervalMs);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }
        log.info("【Mock】BLE 遥测连发完成: sn={}, 帧数={}, 采纳={}",
                sn, acks.size(), acks.stream().filter(TelemetryAck::accepted).count());
        return ApiResponse.success(acks);
    }

    @Operation(summary = "模拟命令执行回执",
            description = "扮演手机网关写入 RX 特征的结果。**回执是状态的唯一提交点**："
                    + "success=true 才会提交静音模式变更；success=false 时保持原状，"
                    + "可用于验证「手机写失败时云端不会错误地认为模式变了」")
    @PostMapping("/devices/{sn}/command/ack")
    public ApiResponse<DeviceVO> commandAck(@PathVariable("sn") String sn,
                                            @RequestParam("command") String command,
                                            @RequestParam(value = "success", defaultValue = "true") boolean success,
                                            @RequestParam(value = "detail", required = false) String detail) {
        Device device = requireBoundDevice(sn);
        return ApiResponse.success(commandService.ack(
                primaryGuardianOf(device), device.getId(),
                new DeviceCommandAckRequest(command, success, detail)));
    }

    private Device requireBoundDevice(String sn) {
        Device device = deviceMapper.selectOne(
                Wrappers.<Device>lambdaQuery().eq(Device::getDeviceSn, sn));
        if (device == null) {
            throw BizException.of(ErrorCode.DEVICE_SN_NOT_FOUND, "模拟设备 " + sn + " 不存在");
        }
        if (device.getWardId() == null) {
            throw BizException.of(ErrorCode.DEVICE_NOT_BOUND,
                    "模拟设备 " + sn + " 尚未绑定被监护人，请先调用 /api/v1/devices/bind 或 demo-reset");
        }
        return device;
    }

    /**
     * Mock 接口没有登录态，只能退化成「取主监护人」作为操作者。
     * 这样做的代价是绕过了 {@code guardianService.requireGuardian}，
     * 所以本类必须只在演示 profile 下注册。
     */
    private Long primaryGuardianOf(Device device) {
        Ward ward = wardMapper.selectById(device.getWardId());
        if (ward == null || ward.getPrimaryUserId() == null) {
            throw BizException.of(ErrorCode.WARD_NOT_FOUND,
                    "被监护人 " + device.getWardId() + " 不存在或没有主监护人");
        }
        return ward.getPrimaryUserId();
    }
}
