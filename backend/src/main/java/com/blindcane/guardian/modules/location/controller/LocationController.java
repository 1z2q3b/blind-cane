package com.blindcane.guardian.modules.location.controller;

import com.blindcane.guardian.common.result.ApiResponse;
import com.blindcane.guardian.framework.security.CurrentUserHolder;
import com.blindcane.guardian.modules.location.dto.LatestLocation;
import com.blindcane.guardian.modules.location.service.LocationService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** 定位查询接口。设备上报入口不对外开放，走 simulator 模块与服务内部调用。 */
@Tag(name = "定位", description = "实时位置查询（读 Redis 热数据）")
@RestController
@RequestMapping("/api/v1/locations")
@RequiredArgsConstructor
public class LocationController {

    private final LocationService locationService;

    @Operation(summary = "最新位置",
            description = "返回 lng/lat/accuracyM/speed/reportedAt；从未上报过则 data 为 null。"
                    + "实时变动请订阅 STOMP /topic/ward/{wardId}/location")
    @GetMapping("/realtime")
    public ApiResponse<LatestLocation> realtime(@RequestParam("wardId") Long wardId) {
        return ApiResponse.success(locationService.latest(CurrentUserHolder.requireUserId(), wardId));
    }
}
