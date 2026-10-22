package com.blindcane.guardian.modules.geofence.service;

import com.blindcane.guardian.modules.geofence.dto.GeofenceCreateRequest;
import com.blindcane.guardian.modules.geofence.dto.GeofenceUpdateRequest;
import com.blindcane.guardian.modules.geofence.dto.GeofenceVO;
import com.blindcane.guardian.modules.geofence.entity.Geofence;

import java.util.List;

/** 电子围栏管理。所有面向家属端的方法都要做监护权限校验。 */
public interface GeofenceService {

    /** 某个被监护人的全部围栏（含停用的，家属需要在列表里看到并重新启用）。 */
    List<GeofenceVO> list(Long userId, Long wardId);

    GeofenceVO create(Long userId, GeofenceCreateRequest request);

    GeofenceVO update(Long userId, Long id, GeofenceUpdateRequest request);

    /** 硬删除：围栏是纯配置数据，不留历史包袱；历史告警里存的是坐标与文案，不依赖围栏记录。 */
    void delete(Long userId, Long id);

    GeofenceVO setEnabled(Long userId, Long id, int enabled);

    /**
     * 取某被监护人名下所有**启用中**的围栏，供命中判定器使用。
     *
     * <p>刻意不接收 userId 也不做权限校验：调用方是位置上报链路（设备侧写入），
     * 那里根本没有"当前登录家属"的概念，强行加校验只会逼调用方造一个假用户。
     */
    List<Geofence> listEnabledByWard(Long wardId);
}
