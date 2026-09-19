package com.blindcane.guardian.modules.location.service.impl;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.blindcane.guardian.common.exception.BizException;
import com.blindcane.guardian.common.result.ErrorCode;
import com.blindcane.guardian.framework.websocket.WsMessageSender;
import com.blindcane.guardian.modules.device.entity.Device;
import com.blindcane.guardian.modules.device.mapper.DeviceMapper;
import com.blindcane.guardian.modules.location.dto.LatestLocation;
import com.blindcane.guardian.modules.location.entity.LocationRecord;
import com.blindcane.guardian.modules.location.service.LocationCacheService;
import com.blindcane.guardian.modules.location.service.LocationFlushBuffer;
import com.blindcane.guardian.modules.location.service.LocationService;
import com.blindcane.guardian.modules.ward.service.GuardianService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.Locale;

@Slf4j
@Service
@RequiredArgsConstructor
public class LocationServiceImpl implements LocationService {

    private final LocationCacheService locationCacheService;
    private final LocationFlushBuffer locationFlushBuffer;
    private final WsMessageSender wsMessageSender;
    private final DeviceMapper deviceMapper;
    private final GuardianService guardianService;

    @Override
    public void report(Long wardId, Long deviceId, Double lng, Double lat,
                       Double accuracyM, Double speed, LocalDateTime reportedAt) {
        if (wardId == null || lng == null || lat == null) {
            throw BizException.of(ErrorCode.PARAM_ERROR, "位置上报缺少 wardId 或坐标");
        }
        if (lng < -180 || lng > 180 || lat < -90 || lat > 90) {
            throw BizException.of(ErrorCode.PARAM_ERROR,
                    "坐标超出合法范围: lng=" + lng + ", lat=" + lat);
        }
        LocalDateTime reportTime = reportedAt == null ? LocalDateTime.now() : reportedAt;
        long reportedAtMillis = reportTime.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli();

        // 逆地理文案在二期接入高德 Web 服务后填入，当前为 null，App 端降级显示坐标
        LatestLocation location = new LatestLocation(lng, lat, accuracyM, speed, reportedAtMillis, null);

        // 1) 实时读路径
        locationCacheService.save(wardId, location);
        // 2) 在线家属实时推送
        wsMessageSender.sendLocation(wardId, location);
        // 3) 历史路径：攒批落 MySQL
        locationFlushBuffer.add(toRecord(wardId, deviceId, location, reportTime));
    }

    @Override
    public void reportByDeviceSn(String deviceSn, Double lng, Double lat, Double accuracyM, Double speed) {
        Device device = deviceMapper.selectOne(Wrappers.<Device>lambdaQuery()
                .eq(Device::getDeviceSn, deviceSn));
        if (device == null) {
            log.warn("收到未知设备 SN 的位置上报，已丢弃: sn={}", deviceSn);
            return;
        }
        if (device.getWardId() == null) {
            // 未绑定设备的数据没有归属，存下来也没人能看到，直接丢弃更干净
            log.debug("设备未绑定被监护人，位置上报已丢弃: sn={}", deviceSn);
            return;
        }
        report(device.getWardId(), device.getId(), lng, lat, accuracyM, speed, LocalDateTime.now());
    }

    @Override
    public LatestLocation latest(Long userId, Long wardId) {
        guardianService.requireGuardian(userId, wardId);
        return locationCacheService.get(wardId);
    }

    // ------------------------------------------------------------------

    private LocationRecord toRecord(Long wardId, Long deviceId, LatestLocation location, LocalDateTime reportTime) {
        LocationRecord record = new LocationRecord();
        record.setWardId(wardId);
        record.setDeviceId(deviceId);
        record.setAccuracyM(location.accuracyM() == null ? null : location.accuracyM().floatValue());
        record.setSpeed(location.speed() == null ? null : location.speed().floatValue());
        record.setReportedAt(reportTime);
        // ⚠️ 坐标顺序是「纬度 经度」，不是常见的「经度 纬度」！
        // MySQL 对地理坐标系 SRID 4326 严格遵循 EPSG:4326 定义的轴序，
        // 即 latitude-longitude（这与 PostGIS 及大多数人写 POINT(lng lat) 的直觉相反）。
        // 若写成 POINT(113.78 ...)，MySQL 会直接报
        //   ERROR 3617: Latitude 113.785000 is out of range in function st_geomfromtext
        // 因为 113.78 被当成纬度了。
        // 另有 String.format 的 Locale 陷阱：某些区域设置会把小数点输出成逗号
        // （113,785），拼进 WKT 会直接语法错误，所以固定使用 Locale.ROOT。
        record.setPointWkt(String.format(Locale.ROOT, "POINT(%f %f)",
                location.lat(), location.lng()));
        return record;
    }
}
