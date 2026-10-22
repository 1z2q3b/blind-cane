package com.blindcane.guardian.modules.device.controller;

import com.blindcane.guardian.common.result.ApiResponse;
import com.blindcane.guardian.framework.security.CurrentUserHolder;
import com.blindcane.guardian.modules.device.dto.BleAddressRequest;
import com.blindcane.guardian.modules.device.dto.DeviceBindRequest;
import com.blindcane.guardian.modules.device.dto.DeviceVO;
import com.blindcane.guardian.modules.device.service.DeviceService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** 导盲杖设备接口。 */
@Tag(name = "设备", description = "SN 码绑定 / 解绑 / 状态查询 / 蓝牙地址登记")
@RestController
@RequestMapping("/api/v1/devices")
@RequiredArgsConstructor
public class DeviceController {

    private final DeviceService deviceService;

    @Operation(summary = "绑定设备",
            description = "演示设备 SN：BC-2024-DEMO01。可同时提交扫描到的手杖蓝牙地址（可选）。"
                    + "SN 不存在返回 104001，已被绑定返回 104002，"
                    + "该被监护人已有设备返回 104005，蓝牙地址被占用返回 104006")
    @PostMapping("/bind")
    public ApiResponse<DeviceVO> bind(@Valid @RequestBody DeviceBindRequest request) {
        return ApiResponse.success(deviceService.bind(CurrentUserHolder.requireUserId(), request));
    }

    @Operation(summary = "解绑设备",
            description = "仅解除归属关系，设备档案保留。同时清空蓝牙地址/障碍状态/静音模式等"
                    + "运行时状态，避免下一任使用者看到上一任留下的脏数据")
    @PostMapping("/{id}/unbind")
    public ApiResponse<Void> unbind(@PathVariable("id") Long id) {
        deviceService.unbind(CurrentUserHolder.requireUserId(), id);
        return ApiResponse.success();
    }

    @Operation(summary = "设备状态",
            description = "电量 / 信号 / 在线 / 最后上报时间 / 蓝牙链路 / 障碍状态 / 播报模式。"
                    + "注意：obstacleStatus 必须在 bleConnected=true 时才是实时值")
    @GetMapping("/{id}/status")
    public ApiResponse<DeviceVO> status(@PathVariable("id") Long id) {
        return ApiResponse.success(deviceService.status(CurrentUserHolder.requireUserId(), id));
    }

    @Operation(summary = "登记 / 刷新手杖蓝牙地址",
            description = "用于家属换手机后更新地址。iOS 给外设分配的 UUID 是每台手机各自随机的，"
                    + "换机后必须重新登记，否则自动重连永远匹配不上")
    @PostMapping("/{id}/ble-address")
    public ApiResponse<DeviceVO> bindBleAddress(@PathVariable("id") Long id,
                                                @Valid @RequestBody BleAddressRequest request) {
        return ApiResponse.success(deviceService.bindBleAddress(
                CurrentUserHolder.requireUserId(), id, request));
    }
}
