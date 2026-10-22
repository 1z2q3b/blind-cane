package com.blindcane.guardian.modules.location.controller;

import com.blindcane.guardian.common.result.ApiResponse;
import com.blindcane.guardian.framework.security.CurrentUserHolder;
import com.blindcane.guardian.modules.location.dto.LatestLocation;
import com.blindcane.guardian.modules.location.dto.TrackPointVO;
import com.blindcane.guardian.modules.location.service.LocationService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/** 定位查询接口。设备上报入口不对外开放，走 simulator 模块与服务内部调用。 */
@Tag(name = "定位", description = "实时位置（读 Redis 热数据）与历史轨迹（读 MySQL，供轨迹回放）")
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

    @Operation(summary = "历史轨迹（轨迹回放）",
            description = "按时间段查历史点位，自动等距降采样到 maxPoints 个点（默认 300，上限 1000）。"
                    + "start/end 支持 yyyy-MM-dd（按整天）或 yyyy-MM-dd HH:mm:ss（精确），"
                    + "不传默认今天；单次跨度最多 7 天。返回按时间升序，末端一定是最后一个点。")
    @GetMapping("/history")
    public ApiResponse<List<TrackPointVO>> history(
            @RequestParam("wardId") Long wardId,
            @RequestParam(value = "start", required = false) String start,
            @RequestParam(value = "end", required = false) String end,
            @RequestParam(value = "maxPoints", required = false) Integer maxPoints) {
        return ApiResponse.success(locationService.history(
                CurrentUserHolder.requireUserId(), wardId, start, end, maxPoints));
    }
}
