package com.blindcane.guardian.modules.geofence.dto;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;

/**
 * 修改围栏请求：**全部字段可选**，只改传上来的那些。
 *
 * <p>这里正好利用了 MyBatis-Plus {@code updateById} 会跳过 null 字段的特性——
 * 以前踩过它的坑（想清空某列时必须用 UpdateWrapper 显式 set），
 * 但在「局部更新」这个场景下它反而是想要的行为，不需要额外判空。
 *
 * <p>wardId 不允许修改：围栏换归属等于新建一条，改归属会让历史告警的关联对不上。
 */
public record GeofenceUpdateRequest(

        @Size(max = 50, message = "围栏名称最多 50 个字符")
        String name,

        @DecimalMin(value = "-180", message = "经度超出合法范围")
        @DecimalMax(value = "180", message = "经度超出合法范围")
        Double centerLng,

        @DecimalMin(value = "-90", message = "纬度超出合法范围")
        @DecimalMax(value = "90", message = "纬度超出合法范围")
        Double centerLat,

        @Min(value = 20, message = "半径不得小于 20 米")
        @Max(value = 5000, message = "半径不得大于 5000 米")
        Integer radiusM,

        @Min(value = 1, message = "围栏类型只能是 1（安全区）或 2（危险区）")
        @Max(value = 2, message = "围栏类型只能是 1（安全区）或 2（危险区）")
        Integer fenceType,

        @Min(value = 0, message = "启用状态只能是 0 或 1")
        @Max(value = 1, message = "启用状态只能是 0 或 1")
        Integer enabled
) {
}
