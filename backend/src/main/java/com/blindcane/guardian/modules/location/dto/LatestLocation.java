package com.blindcane.guardian.modules.location.dto;

/**
 * 最新位置（Redis 热数据）。
 *
 * @param lng        经度
 * @param lat        纬度
 * @param accuracyM  定位精度（米）
 * @param speed      速度（m/s）
 * @param reportedAt 设备上报时间戳（毫秒）
 * @param address    逆地理文案，无高德 Key 时为空，App 端自行降级显示坐标
 */
public record LatestLocation(Double lng, Double lat, Double accuracyM, Double speed,
                             Long reportedAt, String address) {

    public LatestLocation withAddress(String address) {
        return new LatestLocation(lng, lat, accuracyM, speed, reportedAt, address);
    }
}
