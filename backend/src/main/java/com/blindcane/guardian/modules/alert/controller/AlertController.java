package com.blindcane.guardian.modules.alert.controller;

import com.blindcane.guardian.common.result.ApiResponse;
import com.blindcane.guardian.common.result.PageResult;
import com.blindcane.guardian.framework.security.CurrentUserHolder;
import com.blindcane.guardian.modules.alert.dto.AlertHandleRequest;
import com.blindcane.guardian.modules.alert.dto.AlertVO;
import com.blindcane.guardian.modules.alert.dto.PendingCountVO;
import com.blindcane.guardian.modules.alert.service.AlertCenterService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** 告警中心接口。 */
@Tag(name = "告警中心", description = "历史列表筛选分页、待处理角标、处理/误报标记")
@RestController
@RequestMapping("/api/v1/alerts")
@RequiredArgsConstructor
public class AlertController {

    private final AlertCenterService alertCenterService;

    @Operation(summary = "告警历史（分页筛选）",
            description = "wardId 为空时查名下全部被监护人；type 如 SOS / FALL_DETECTED / LOW_BATTERY / DEVICE_OFFLINE；"
                    + "status：0 待处理 / 1 已处理 / 2 误报")
    @GetMapping
    public ApiResponse<PageResult<AlertVO>> query(
            @RequestParam(value = "wardId", required = false) Long wardId,
            @RequestParam(value = "type", required = false) String type,
            @RequestParam(value = "status", required = false) Integer status,
            @RequestParam(value = "page", defaultValue = "1") long page,
            @RequestParam(value = "size", defaultValue = "20") long size) {
        return ApiResponse.success(alertCenterService.query(
                CurrentUserHolder.requireUserId(), wardId, type, status, page, size));
    }

    @Operation(summary = "待处理告警数量", description = "返回总数与分被监护人明细，供 App 角标使用")
    @GetMapping("/pending-count")
    public ApiResponse<PendingCountVO> pendingCount() {
        return ApiResponse.success(alertCenterService.pendingCount(CurrentUserHolder.requireUserId()));
    }

    @Operation(summary = "告警详情")
    @GetMapping("/{id}")
    public ApiResponse<AlertVO> detail(@PathVariable("id") Long id) {
        return ApiResponse.success(alertCenterService.detail(CurrentUserHolder.requireUserId(), id));
    }

    @Operation(summary = "处理告警", description = "result 取 RESOLVED（已处理）或 FALSE_ALARM（误报）；已处理的告警再处理返回 106002")
    @PutMapping("/{id}/handle")
    public ApiResponse<AlertVO> handle(@PathVariable("id") Long id,
                                       @Valid @RequestBody AlertHandleRequest request) {
        return ApiResponse.success(alertCenterService.handle(CurrentUserHolder.requireUserId(), id, request));
    }
}
