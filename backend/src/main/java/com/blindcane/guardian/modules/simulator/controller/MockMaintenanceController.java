package com.blindcane.guardian.modules.simulator.controller;

import com.blindcane.guardian.common.result.ApiResponse;
import com.blindcane.guardian.common.result.ErrorCode;
import com.blindcane.guardian.common.exception.BizException;
import com.blindcane.guardian.framework.config.BlindcaneProperties;
import com.blindcane.guardian.framework.redis.RedisGuard;
import com.blindcane.guardian.modules.device.entity.Device;
import com.blindcane.guardian.modules.device.mapper.DeviceMapper;
import com.blindcane.guardian.modules.device.service.DeviceService;
import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDateTime;
import java.util.Objects;

/**
 * 设备模拟器 · 演示数据维护接口（演示专用）。
 *
 * <p>为什么需要这个接口：开发与演示时同一个手机号一天会登录十几次，
 * 很快就会撞上「今日验证码发送次数已达上限」——这是提示词 5.1 明确要求的
 * 业务规则，不能为了图方便把它去掉，否则演示环境与生产环境的行为就不一致了。
 * 所以另开一个只在 {@code blindcane.simulator.enabled=true} 时存在的维护接口，
 * 用来把限流状态清干净。
 *
 * <p>真正的业务约束一条都没放松：生产 profile 下本类不会注册，
 * 且 Redis 里的限流 key 仍然按原有 TTL 正常失效。
 */
@Slf4j
@Tag(name = "Mock · 演示维护", description = "演示专用：重置短信限流、恢复演示数据")
@RestController
@RequestMapping("/api/v1/mock")
@RequiredArgsConstructor
@ConditionalOnProperty(name = "blindcane.simulator.enabled", havingValue = "true", matchIfMissing = true)
public class MockMaintenanceController {

    private static final String KEY_SMS_CODE = "auth:sms:code:";
    private static final String KEY_SMS_INTERVAL = "auth:sms:interval:";
    private static final String KEY_SMS_DAILY = "auth:sms:daily:";

    private final StringRedisTemplate redisTemplate;
    private final RedisGuard redisGuard;
    private final DeviceMapper deviceMapper;
    private final DeviceService deviceService;
    private final BlindcaneProperties properties;

    @Operation(summary = "重置指定手机号的短信限流",
            description = "清掉验证码、60 秒发送间隔、每日次数三项计数。手机号留空则清全部（仅演示用）")
    @PostMapping("/sms/reset")
    public ApiResponse<String> resetSms(@RequestParam(value = "phone", required = false) String phone) {
        if (phone == null || phone.isBlank()) {
            Long removed = deleteByPattern(KEY_SMS_CODE + "*")
                    + deleteByPattern(KEY_SMS_INTERVAL + "*")
                    + deleteByPattern(KEY_SMS_DAILY + "*");
            log.info("【Mock】已清空全部短信限流状态，删除 {} 个 key", removed);
            return ApiResponse.success("已清空全部短信限流状态，共删除 " + removed + " 个 key");
        }
        redisGuard.run(() -> redisTemplate.delete(KEY_SMS_CODE + phone));
        redisGuard.run(() -> redisTemplate.delete(KEY_SMS_INTERVAL + phone));
        redisGuard.run(() -> redisTemplate.delete(KEY_SMS_DAILY + phone));
        log.info("【Mock】已重置手机号 {} 的短信限流状态", phone);
        return ApiResponse.success("已重置手机号 " + phone + " 的短信限流状态");
    }

    @Operation(summary = "把演示设备恢复为可演示状态",
            description = "电量回满、恢复在线，用于两次演示之间快速复位（不清位置与告警历史）")
    @PostMapping("/devices/{sn}/reset")
    public ApiResponse<String> resetDevice(@PathVariable("sn") String sn) {
        if (!properties.getSimulator().isEnabled()) {
            throw BizException.of(ErrorCode.RESOURCE_NOT_FOUND, "设备模拟器未启用");
        }
        Device device = deviceMapper.selectOne(Wrappers.<Device>lambdaQuery()
                .eq(Device::getDeviceSn, sn));
        if (device == null) {
            throw BizException.of(ErrorCode.DEVICE_SN_NOT_FOUND, "模拟设备 " + sn + " 不存在");
        }
        int initialBattery = properties.getSimulator().getInitialBattery();
        // 走真实上报入口：顺带复位离线去抖标记、刷新在线状态并推送一次设备状态
        deviceService.recordReport(device.getId(), initialBattery, 4, LocalDateTime.now());
        log.info("【Mock】演示设备已复位: sn={}, deviceId={}, 电量={}%",
                sn, device.getId(), initialBattery);
        return ApiResponse.success("演示设备 " + sn + " 已复位（电量 " + initialBattery + "%、已恢复在线）");
    }

    /** Redis 的 KEYS 在生产是禁忌，但本接口只在演示 profile 下存在，且 key 空间很小。 */
    private long deleteByPattern(String pattern) {
        var keys = redisGuard.call(() -> redisTemplate.keys(pattern), () -> null);
        if (keys == null || keys.isEmpty()) {
            return 0;
        }
        Long removed = redisGuard.call(() -> redisTemplate.delete(keys), () -> 0L);
        return Objects.requireNonNullElse(removed, 0L);
    }
}
