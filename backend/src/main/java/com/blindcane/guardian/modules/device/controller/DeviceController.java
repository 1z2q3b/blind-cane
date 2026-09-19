package com.blindcane.guardian.modules.device.controller;

import com.blindcane.guardian.common.result.ApiResponse;
import com.blindcane.guardian.framework.security.CurrentUserHolder;
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
@Tag(name = "设备", description = "SN 码绑定 / 解绑 / 状态查询")
@RestController
@RequestMapping("/api/v1/devices")
@RequiredArgsConstructor
public class DeviceController {

    private final DeviceService deviceService;

    @Operation(summary = "绑定设备",
            description = "演示设备 SN：BC-2024-DEMO01。SN 不存在返回 104001，已被绑定返回 104002，"
                    + "该被监护人已有设备返回 104005")
    @PostMapping("/bind")
    public ApiResponse<DeviceVO> bind(@Valid @RequestBody DeviceBindRequest request) {
        return ApiResponse.success(deviceService.bind(CurrentUserHolder.requireUserId(), request));
    }

    @Operation(summary = "解绑设备", description = "仅解除归属关系，设备档案保留")
    @PostMapping("/{id}/unbind")
    public ApiResponse<Void> unbind(@PathVariable("id") Long id) {
        deviceService.unbind(CurrentUserHolder.requireUserId(), id);
        return ApiResponse.success();
    }

    @Operation(summary = "设备状态", description = "电量百分比 / 信号强度 / 在线状态 / 最后上报时间")
    @GetMapping("/{id}/status")
    public ApiResponse<DeviceVO> status(@PathVariable("id") Long id) {
        return ApiResponse.success(deviceService.status(CurrentUserHolder.requireUserId(), id));
    }
}
