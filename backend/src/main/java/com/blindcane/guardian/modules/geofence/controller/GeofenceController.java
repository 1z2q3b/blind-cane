package com.blindcane.guardian.modules.geofence.controller;

import com.blindcane.guardian.common.result.ApiResponse;
import com.blindcane.guardian.framework.security.CurrentUserHolder;
import com.blindcane.guardian.modules.geofence.dto.GeofenceCreateRequest;
import com.blindcane.guardian.modules.geofence.dto.GeofenceUpdateRequest;
import com.blindcane.guardian.modules.geofence.dto.GeofenceVO;
import com.blindcane.guardian.modules.geofence.service.GeofenceService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 电子围栏接口。
 *
 * <p>全部接口都要求登录，并且只能操作自己名下的被监护人的围栏
 * （权限校验在 Service 层用 guardianService.requireGuardian 做）。
 */
@Tag(name = "电子围栏", description = "圆形围栏的增删改查与启停；命中判定由位置上报链路自动完成")
@RestController
@RequestMapping("/api/v1/geofences")
@RequiredArgsConstructor
public class GeofenceController {

    private final GeofenceService geofenceService;

    @Operation(summary = "围栏列表", description = "返回该被监护人的全部围栏，含已停用的（enabled=0）")
    @GetMapping
    public ApiResponse<List<GeofenceVO>> list(@RequestParam("wardId") Long wardId) {
        return ApiResponse.success(geofenceService.list(CurrentUserHolder.requireUserId(), wardId));
    }

    @Operation(summary = "新建围栏",
            description = "fenceType：1 安全区（离开时告警）/ 2 危险区（进入时告警）。半径 20~5000 米")
    @PostMapping
    public ApiResponse<GeofenceVO> create(@Valid @RequestBody GeofenceCreateRequest request) {
        return ApiResponse.success(geofenceService.create(CurrentUserHolder.requireUserId(), request));
    }

    @Operation(summary = "修改围栏", description = "局部更新，只传需要改的字段；wardId 不可修改")
    @PutMapping("/{id}")
    public ApiResponse<GeofenceVO> update(@PathVariable("id") Long id,
                                          @Valid @RequestBody GeofenceUpdateRequest request) {
        return ApiResponse.success(geofenceService.update(CurrentUserHolder.requireUserId(), id, request));
    }

    @Operation(summary = "删除围栏")
    @DeleteMapping("/{id}")
    public ApiResponse<Void> delete(@PathVariable("id") Long id) {
        geofenceService.delete(CurrentUserHolder.requireUserId(), id);
        return ApiResponse.success();
    }

    @Operation(summary = "启用 / 停用围栏",
            description = "enabled=1 启用，0 停用。停用后不再参与命中判定，但记录保留")
    @PutMapping("/{id}/enabled")
    public ApiResponse<GeofenceVO> setEnabled(@PathVariable("id") Long id,
                                              @RequestParam("enabled") int enabled) {
        return ApiResponse.success(
                geofenceService.setEnabled(CurrentUserHolder.requireUserId(), id, enabled));
    }
}
