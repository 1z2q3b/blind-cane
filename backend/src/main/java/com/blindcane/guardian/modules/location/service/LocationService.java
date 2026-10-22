package com.blindcane.guardian.modules.location.service;

import com.blindcane.guardian.modules.location.dto.LatestLocation;
import com.blindcane.guardian.modules.location.dto.TrackPointVO;

import java.time.LocalDateTime;
import java.util.List;

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

    /**
     * 历史轨迹（用于轨迹回放）。
     *
     * <p>时间参数接受两种写法，传 null 时默认取「今天」：
     * <ul>
     *   <li>{@code 2026-10-21} —— 按整天算，左闭右开</li>
     *   <li>{@code 2026-10-21T08:30:00} / {@code 2026-10-21 08:30:00} —— 精确到秒</li>
     * </ul>
     *
     * @param maxPoints 返回点数的上限，超过则等距抽样降采样；null 用默认 300
     */
    List<TrackPointVO> history(Long userId, Long wardId, String start, String end, Integer maxPoints);
}
