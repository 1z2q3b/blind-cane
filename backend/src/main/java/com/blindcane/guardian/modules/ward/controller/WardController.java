package com.blindcane.guardian.modules.ward.controller;

import com.blindcane.guardian.common.result.ApiResponse;
import com.blindcane.guardian.framework.security.CurrentUserHolder;
import com.blindcane.guardian.modules.ward.dto.WardCreateRequest;
import com.blindcane.guardian.modules.ward.dto.WardDeleteResultVO;
import com.blindcane.guardian.modules.ward.dto.WardDetailVO;
import com.blindcane.guardian.modules.ward.dto.WardUpdateRequest;
import com.blindcane.guardian.modules.ward.dto.WardVO;
import com.blindcane.guardian.modules.ward.service.WardService;
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
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/** 被监护人档案接口。所有接口都隐含一次监护权限校验。 */
@Tag(name = "被监护人", description = "档案 CRUD；创建者自动成为主监护人")
@RestController
@RequestMapping("/api/v1/wards")
@RequiredArgsConstructor
public class WardController {

    private final WardService wardService;

    @Operation(summary = "创建被监护人档案", description = "创建者自动登记为主监护人（role=1，已接受）")
    @PostMapping
    public ApiResponse<WardDetailVO> create(@Valid @RequestBody WardCreateRequest request) {
        return ApiResponse.success(wardService.create(CurrentUserHolder.requireUserId(), request));
    }

    @Operation(summary = "我的被监护人列表",
            description = "含设备状态、最新位置摘要、待处理告警数；不含病史备注（病史只在详情接口返回）")
    @GetMapping
    public ApiResponse<List<WardVO>> list() {
        return ApiResponse.success(wardService.listMine(CurrentUserHolder.requireUserId()));
    }

    @Operation(summary = "被监护人详情", description = "病史备注在此接口解密返回，需通过监护权限校验")
    @GetMapping("/{id}")
    public ApiResponse<WardDetailVO> detail(@PathVariable("id") Long id) {
        return ApiResponse.success(wardService.detail(CurrentUserHolder.requireUserId(), id));
    }

    @Operation(summary = "更新被监护人档案", description = "字段可选，传 null 表示不修改")
    @PutMapping("/{id}")
    public ApiResponse<WardDetailVO> update(@PathVariable("id") Long id,
                                            @Valid @RequestBody WardUpdateRequest request) {
        return ApiResponse.success(wardService.update(CurrentUserHolder.requireUserId(), id, request));
    }

    @Operation(summary = "删除被监护人档案",
            description = "仅主监护人可调用。会连带清理该档案的围栏、位置流水、告警历史与监护关系；"
                    + "已绑定的手杖会被解绑（不删除设备本身）")
    @DeleteMapping("/{id}")
    public ApiResponse<WardDeleteResultVO> delete(@PathVariable("id") Long id) {
        return ApiResponse.success(wardService.delete(CurrentUserHolder.requireUserId(), id));
    }
}
