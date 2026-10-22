package com.blindcane.guardian.modules.location.dto;

import java.time.LocalDateTime;

/**
 * 轨迹回放中的一个点。
 *
 * @param lng        经度
 * @param lat        纬度
 * @param reportedAt 上报时间（App 按这个排序与计算回放节奏）
 * @param speed      速度 m/s，可能为空
 * @param accuracyM  定位精度（米），可能为空
 */
public record TrackPointVO(Double lng, Double lat, LocalDateTime reportedAt,
                           Float speed, Float accuracyM) {
}
