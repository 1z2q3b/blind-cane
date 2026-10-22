package com.blindcane.guardian.modules.location.service.impl;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.blindcane.guardian.common.exception.BizException;
import com.blindcane.guardian.common.result.ErrorCode;
import com.blindcane.guardian.framework.websocket.WsMessageSender;
import com.blindcane.guardian.modules.device.entity.Device;
import com.blindcane.guardian.modules.device.mapper.DeviceMapper;
import com.blindcane.guardian.modules.geofence.service.GeofenceEvaluator;
import com.blindcane.guardian.modules.location.dto.LatestLocation;
import com.blindcane.guardian.modules.location.dto.TrackPointVO;
import com.blindcane.guardian.modules.location.dto.TrackRow;
import com.blindcane.guardian.modules.location.entity.LocationRecord;
import com.blindcane.guardian.modules.location.mapper.LocationRecordMapper;
import com.blindcane.guardian.modules.location.service.LocationCacheService;
import com.blindcane.guardian.modules.location.service.LocationFlushBuffer;
import com.blindcane.guardian.modules.location.service.LocationService;
import com.blindcane.guardian.modules.ward.service.GuardianService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.List;
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
    private final GeofenceEvaluator geofenceEvaluator;
    private final LocationRecordMapper locationRecordMapper;

    /** 轨迹一次最多查多少原始行。按 10 秒一条算，一天 8640 条，7 天约 6 万条，这里卡 2 万防止极端情况打爆内存。 */
    private static final int RAW_SCAN_LIMIT = 20_000;
    private static final int DEFAULT_MAX_POINTS = 300;
    private static final int MAX_POINTS_CAP = 1000;
    /** 单次查询最长跨度。再长就不是"回放"而是"数据导出"了，应该走离线导出。 */
    private static final int MAX_SPAN_DAYS = 7;

    private static final DateTimeFormatter DATE_TIME_FORMAT =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

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
        // 4) 电子围栏判定（旁路增强：内部吞异常，绝不会让上报失败）
        geofenceEvaluator.evaluate(wardId, deviceId, lng, lat);
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

    @Override
    public List<TrackPointVO> history(Long userId, Long wardId, String start, String end, Integer maxPoints) {
        guardianService.requireGuardian(userId, wardId);

        LocalDate today = LocalDate.now();
        LocalDateTime from = parseTime(start, today.atStartOfDay(), true);
        LocalDateTime to = parseTime(end, today.plusDays(1).atStartOfDay(), false);

        if (!to.isAfter(from)) {
            throw BizException.of(ErrorCode.PARAM_ERROR, "结束时间必须晚于开始时间");
        }
        if (to.isAfter(from.plusDays(MAX_SPAN_DAYS))) {
            throw BizException.of(ErrorCode.PARAM_ERROR,
                    "单次最多查询 " + MAX_SPAN_DAYS + " 天的轨迹");
        }

        int limit = maxPoints == null
                ? DEFAULT_MAX_POINTS
                : Math.max(2, Math.min(maxPoints, MAX_POINTS_CAP));

        List<TrackRow> rows = locationRecordMapper.selectTrack(wardId, from, to, RAW_SCAN_LIMIT);
        log.debug("轨迹查询: wardId={}, {} ~ {}, 原始 {} 条, 目标点数 {}",
                wardId, from, to, rows.size(), limit);
        return downsample(rows, limit);
    }

    // ------------------------------------------------------------------

    /**
     * 解析时间参数。
     *
     * <p>只传日期（10 位）时按「整天」理解：开始取当天 00:00，结束取次日 00:00，
     * 这样前端选「10 月 21 日」拿到的是完整一天，不用自己拼时分秒。
     * 传了时分秒就按精确时间处理。两种写法都支持空格和 T 分隔，
     * 因为 Flutter 的 DateTime.toIso8601String() 输出的是 T，而人手工输入习惯是空格。
     */
    private LocalDateTime parseTime(String raw, LocalDateTime fallback, boolean isStart) {
        if (raw == null || raw.isBlank()) {
            return fallback;
        }
        String value = raw.trim();
        try {
            if (value.length() == 10) {
                LocalDate date = LocalDate.parse(value);
                return isStart ? date.atStartOfDay() : date.plusDays(1).atStartOfDay();
            }
            return LocalDateTime.parse(value.replace('T', ' '), DATE_TIME_FORMAT);
        } catch (DateTimeParseException e) {
            throw BizException.of(ErrorCode.PARAM_ERROR,
                    "时间格式不正确，应为 yyyy-MM-dd 或 yyyy-MM-dd HH:mm:ss，实际: " + value);
        }
    }

    /**
     * 等距抽样降采样。
     *
     * <p>为什么不做「按距离抽稀」（Douglas-Peucker）：回放需要保持**时间轴均匀**，
     * 否则老人在原地停留时点会挤成一坨、走动时突然跳跃，播放速度看起来忽快忽慢。
     * 等距抽样能保证回放进度条与真实时间成正比。
     *
     * <p>用 Math.round(i * step) 而不是 i * step 取整：后者会让最后一个点取不到
     * 终点（终点往往是家属最关心的"最后出现在哪"）。
     */
    private List<TrackPointVO> downsample(List<TrackRow> rows, int limit) {
        if (rows.isEmpty()) {
            return List.of();
        }
        if (rows.size() <= limit) {
            return rows.stream().map(LocationServiceImpl::toVO).toList();
        }
        List<TrackPointVO> sampled = new ArrayList<>(limit);
        double step = (rows.size() - 1.0) / (limit - 1.0);
        for (int i = 0; i < limit; i++) {
            sampled.add(toVO(rows.get((int) Math.round(i * step))));
        }
        return sampled;
    }

    private static TrackPointVO toVO(TrackRow row) {
        return new TrackPointVO(row.getLng(), row.getLat(), row.getReportedAt(),
                row.getSpeed(), row.getAccuracyM());
    }

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
