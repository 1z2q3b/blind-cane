package com.blindcane.guardian.modules.simulator.controller;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.blindcane.guardian.common.exception.BizException;
import com.blindcane.guardian.common.result.ApiResponse;
import com.blindcane.guardian.common.result.ErrorCode;
import com.blindcane.guardian.framework.config.BlindcaneProperties;
import com.blindcane.guardian.modules.alert.dto.AlertCreateCommand;
import com.blindcane.guardian.modules.alert.dto.AlertVO;
import com.blindcane.guardian.modules.alert.entity.AlertRecord;
import com.blindcane.guardian.modules.alert.entity.AlertType;
import com.blindcane.guardian.modules.alert.service.AlertService;
import com.blindcane.guardian.modules.alert.service.impl.AlertServiceImpl;
import com.blindcane.guardian.modules.device.dto.DeviceVO;
import com.blindcane.guardian.modules.device.entity.Device;
import com.blindcane.guardian.modules.device.mapper.DeviceMapper;
import com.blindcane.guardian.modules.device.service.DeviceService;
import com.blindcane.guardian.modules.location.dto.LatestLocation;
import com.blindcane.guardian.modules.location.service.LocationCacheService;
import com.blindcane.guardian.modules.location.service.LocationService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 设备模拟器 · 设备状态类 Mock 接口（演示专用）。
 *
 * <p>整个 Controller 受 {@code blindcane.simulator.enabled} 控制：
 * 生产 profile 下 Bean 根本不会注册，配合 SecurityConfig 的路径策略，
 * /api/v1/mock/** 会彻底消失，不存在「忘了关 Mock」的风险。
 *
 * <p>6 个 Mock 接口覆盖了提示词 6.6 要求的全部演示动作：
 * 查看设备、设置电量、切换在线、上报位置、一键求助（SOS）、跌倒（含取消）。
 */
@Slf4j
@Tag(name = "Mock · 设备模拟器", description = "演示专用：制造电量/在线/位置/告警变化，驱动真实业务链路")
@RestController
@RequestMapping("/api/v1/mock/devices")
@RequiredArgsConstructor
@ConditionalOnProperty(name = "blindcane.simulator.enabled", havingValue = "true", matchIfMissing = true)
public class MockDeviceController {

    private final DeviceMapper deviceMapper;
    private final DeviceService deviceService;
    private final LocationService locationService;
    private final LocationCacheService locationCacheService;
    private final AlertService alertService;
    private final BlindcaneProperties properties;

    @Operation(summary = "查看全部模拟设备", description = "确认演示设备是否已注册")
    @GetMapping
    public ApiResponse<List<DeviceVO>> list() {
        return ApiResponse.success(deviceMapper.selectList(Wrappers.<Device>lambdaQuery())
                .stream().map(DeviceVO::from).toList());
    }

    @Operation(summary = "设置设备电量",
            description = "走真实上报入口，因此会触发低电量阶梯告警。低于 20% 后每跌 10% 告警一次")
    @PostMapping("/{sn}/battery")
    public ApiResponse<DeviceVO> setBattery(@PathVariable("sn") String sn,
                                            @RequestParam("level") Integer level) {
        if (level == null || level < 0 || level > 100) {
            throw BizException.of(ErrorCode.PARAM_ERROR, "电量必须在 0-100 之间");
        }
        Device device = requireDevice(sn);
        // 信号强度固定给 4 而不是沿用库里存的值：这次上报本身意味着设备在线，
        // 若沿用上一轮离线时被置 0 的信号值，会出现「在线但信号为 0」的矛盾状态
        deviceService.recordReport(device.getId(), level, 4, LocalDateTime.now());
        log.info("【Mock】设备 {} 电量已设为 {}%", sn, level);
        return ApiResponse.success(DeviceVO.from(deviceMapper.selectById(device.getId())));
    }

    @Operation(summary = "切换设备在线状态",
            description = "切为离线时可通过 ageMinutes 把「最后上报时间」往前拨，"
                    + "这样不必真等 5 分钟就能触发离线检测任务")
    @PostMapping("/{sn}/toggle-online")
    public ApiResponse<DeviceVO> toggleOnline(@PathVariable("sn") String sn,
                                              @RequestParam(value = "ageMinutes", defaultValue = "0") long ageMinutes) {
        Device device = requireDevice(sn);
        boolean currentlyOnline = device.getOnline() != null && device.getOnline() == Device.ONLINE;

        if (currentlyOnline) {
            // 需要显式 set null/0，所以用 UpdateWrapper 而不是 updateById
            deviceMapper.update(null, Wrappers.<Device>lambdaUpdate()
                    .eq(Device::getId, device.getId())
                    .set(Device::getOnline, Device.OFFLINE)
                    .set(Device::getSignalLevel, 0)
                    .set(Device::getLastOnlineAt, LocalDateTime.now().minusMinutes(Math.max(0, ageMinutes))));
            log.info("【Mock】设备 {} 已切换为离线（最后上报时间前拨 {} 分钟）", sn, ageMinutes);
        } else {
            // 恢复在线走真实上报入口，会自动复位离线去抖标记
            deviceService.recordReport(device.getId(), device.getBattery(), 4, LocalDateTime.now());
            log.info("【Mock】设备 {} 已恢复在线", sn);
        }
        return ApiResponse.success(DeviceVO.from(deviceMapper.selectById(device.getId())));
    }

    @Operation(summary = "模拟一次位置上报",
            description = "走真实位置链路：写 Redis 最新位置 + STOMP 广播 + 进入批量落库队列。"
                    + "不传坐标时优先沿用该被监护人的最新位置（Redis），没有则退回配置起点")
    @PostMapping("/{sn}/location")
    public ApiResponse<LatestLocation> reportLocation(
            @PathVariable("sn") String sn,
            @RequestParam(value = "lng", required = false) Double lng,
            @RequestParam(value = "lat", required = false) Double lat,
            @RequestParam(value = "accuracy", required = false, defaultValue = "12.5") Double accuracy,
            @RequestParam(value = "speed", required = false, defaultValue = "1.1") Double speed) {
        Device device = requireDevice(sn);
        BlindcaneProperties.Simulator sim = properties.getSimulator();

        // 不传坐标时沿用最新位置而不是回退到固定起点：
        // 否则演示时「手动上报一次」会把地图上的点瞬移回起点，看着像 bug。
        LatestLocation latest = device.getWardId() == null
                ? null
                : locationCacheService.get(device.getWardId());
        double finalLng = lng != null ? lng
                : (latest != null && latest.lng() != null ? latest.lng() : sim.getOriginLng());
        double finalLat = lat != null ? lat
                : (latest != null && latest.lat() != null ? latest.lat() : sim.getOriginLat());

        locationService.reportByDeviceSn(sn, finalLng, finalLat, accuracy, speed);
        log.info("【Mock】设备 {} 位置上报: ({}, {})", sn, finalLng, finalLat);
        return ApiResponse.success(new LatestLocation(finalLng, finalLat, accuracy, speed,
                System.currentTimeMillis(), null));
    }

    private Device requireDevice(String sn) {
        Device device = deviceMapper.selectOne(Wrappers.<Device>lambdaQuery().eq(Device::getDeviceSn, sn));
        if (device == null) {
            throw BizException.of(ErrorCode.DEVICE_SN_NOT_FOUND, "模拟设备 " + sn + " 不存在");
        }
        return device;
    }

    // ==================================================================
    // SOS / 跌倒（提示词 5.8 / 6.6）
    // ==================================================================

    @Operation(summary = "模拟一键求助（SOS）",
            description = "直接产生 severity=1 的紧急告警，家属端应立即全屏强提醒。"
                    + "不传坐标时自动带上 Redis 里的最新位置")
    @PostMapping("/{sn}/sos")
    public ApiResponse<AlertVO> sos(@PathVariable("sn") String sn,
                                   @RequestParam(value = "lng", required = false) Double lng,
                                   @RequestParam(value = "lat", required = false) Double lat,
                                   @RequestParam(value = "note", required = false) String note) {
        Device device = requireBoundDevice(sn);
        AlertRecord alert = alertService.create(AlertCreateCommand
                .withLocation(device.getWardId(), device.getId(), AlertType.SOS,
                        lng, lat, null)
                .withNote(note == null || note.isBlank() ? "老人按下手杖 SOS 按键" : note));
        log.info("【Mock】模拟 SOS: sn={}, alertId={}", sn, alert.getId());
        return ApiResponse.success(AlertVO.from(alert, null));
    }

    @Operation(summary = "模拟跌倒检测（疑似，30 秒后自动升级）",
            description = "先产生 severity=2 的疑似告警，家属端显示警示 + 确认倒计时；"
                    + "30 秒内不调用 cancel 接口，会被定时任务升级为 severity=1 的紧急告警")
    @PostMapping("/{sn}/fall")
    public ApiResponse<AlertVO> fall(@PathVariable("sn") String sn,
                                     @RequestParam(value = "lng", required = false) Double lng,
                                     @RequestParam(value = "lat", required = false) Double lat) {
        Device device = requireBoundDevice(sn);
        int timeout = properties.getSimulator().getFallConfirmTimeoutSeconds();
        AlertRecord alert = alertService.create(AlertCreateCommand
                .withLocation(device.getWardId(), device.getId(), AlertType.FALL_DETECTED,
                        lng, lat, null)
                .withSeverity(AlertServiceImpl.SUSPECT_SEVERITY)
                .asPendingConfirm()
                .withNote("杖体加速度计检测到疑似跌倒，" + timeout + " 秒内未取消将升级为紧急告警"));
        log.info("【Mock】模拟跌倒（疑似）: sn={}, alertId={}, 确认窗口={}s", sn, alert.getId(), timeout);
        return ApiResponse.success(AlertVO.from(alert, null));
    }

    @Operation(summary = "取消疑似跌倒（杖体按键 / 家属判定误报）",
            description = "把告警标记为误报并推送一条撤销消息，App 端据此撤掉确认倒计时条")
    @PostMapping("/{sn}/fall/{alertId}/cancel")
    public ApiResponse<AlertVO> cancelFall(@PathVariable("sn") String sn,
                                           @PathVariable("alertId") Long alertId,
                                           @RequestParam(value = "note", required = false) String note) {
        requireBoundDevice(sn);
        AlertRecord alert = alertService.cancelPendingFall(alertId, note);
        if (alert == null) {
            // 既能是"告警不存在"，也能是"已经取消过 / 已经升级过"——
            // 对演示者来说都是"当前没什么可取消的"，用同一个错误码避免误判
            throw BizException.of(ErrorCode.RESOURCE_NOT_FOUND,
                    "疑似跌倒告警不存在或已结束确认流程: alertId=" + alertId);
        }
        log.info("【Mock】疑似跌倒已取消: sn={}, alertId={}", sn, alertId);
        return ApiResponse.success(AlertVO.from(alert, null));
    }

    /** Mock 接口只服务已绑定设备：未绑定设备产生告警没有归属，家属端看不到。 */
    private Device requireBoundDevice(String sn) {
        Device device = requireDevice(sn);
        if (device.getWardId() == null) {
            throw BizException.of(ErrorCode.DEVICE_NOT_BOUND, "模拟设备 " + sn + " 尚未绑定被监护人");
        }
        return device;
    }
}
