package com.blindcane.guardian.modules.geofence.dto;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * 新建围栏请求。
 *
 * <p>半径下限 20 米、上限 5000 米不是拍脑袋：小于是 20 米时 GPS 精度误差（手机通常
 * 10~30 米）本身就会让围栏反复误触发；大于 5 公里则围栏失去"日常活动范围"的意义。
 */
public record GeofenceCreateRequest(

        @NotNull(message = "wardId 不能为空")
        Long wardId,

        @NotBlank(message = "围栏名称不能为空")
        @Size(max = 50, message = "围栏名称最多 50 个字符")
        String name,

        @NotNull(message = "中心点经度不能为空")
        @DecimalMin(value = "-180", message = "经度超出合法范围")
        @DecimalMax(value = "180", message = "经度超出合法范围")
        Double centerLng,

        @NotNull(message = "中心点纬度不能为空")
        @DecimalMin(value = "-90", message = "纬度超出合法范围")
        @DecimalMax(value = "90", message = "纬度超出合法范围")
        Double centerLat,

        @NotNull(message = "半径不能为空")
        @Min(value = 20, message = "半径不得小于 20 米")
        @Max(value = 5000, message = "半径不得大于 5000 米")
        Integer radiusM,

        @NotNull(message = "围栏类型不能为空")
        @Min(value = 1, message = "围栏类型只能是 1（安全区）或 2（危险区）")
        @Max(value = 2, message = "围栏类型只能是 1（安全区）或 2（危险区）")
        Integer fenceType,

        /** 不传默认启用。 */
        Integer enabled
) {
}
