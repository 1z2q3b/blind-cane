package com.blindcane.guardian.modules.location.service;

import com.blindcane.guardian.modules.location.dto.LatestLocation;

import java.time.LocalDateTime;

/** 位置服务：接收上报（双写）与实时查询。 */
public interface LocationService {

    /**
     * 接收一次位置上报。
     *
     * <p>链路（提示词 4.3）：写 Redis 最新位置 → STOMP 广播 → 进入批量落库队列。
     * 顺序不能改：家属端打开地图时读的是 Redis，必须先写才有实时性可言。
     */
    void report(Long wardId, Long deviceId, Double lng, Double lat,
                Double accuracyM, Double speed, LocalDateTime reportedAt);

    /** 以设备 SN 上报（模拟器与未来的设备网关入口）。未绑定设备会被忽略。 */
    void reportByDeviceSn(String deviceSn, Double lng, Double lat, Double accuracyM, Double speed);

    /** 查最新位置（需通过监护权限校验）。 */
    LatestLocation latest(Long userId, Long wardId);
}
