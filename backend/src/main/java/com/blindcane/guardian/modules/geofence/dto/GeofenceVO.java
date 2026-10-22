package com.blindcane.guardian.modules.geofence.dto;

import com.blindcane.guardian.modules.geofence.entity.Geofence;

import java.time.LocalDateTime;

/**
 * 围栏展示对象。
 *
 * @param fenceType 1 安全区 / 2 危险区
 * @param enabled   0 关 / 1 开
 */
public record GeofenceVO(Long id, Long wardId, String name,
                         Double centerLng, Double centerLat, Integer radiusM,
                         Integer fenceType, Integer enabled,
                         LocalDateTime createdAt) {

    public static GeofenceVO from(Geofence entity) {
        return new GeofenceVO(entity.getId(), entity.getWardId(), entity.getName(),
                entity.getCenterLng(), entity.getCenterLat(), entity.getRadiusM(),
                entity.getFenceType(), entity.getEnabled(), entity.getCreatedAt());
    }
}
