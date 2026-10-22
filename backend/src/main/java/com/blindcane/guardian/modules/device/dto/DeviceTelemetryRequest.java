package com.blindcane.guardian.modules.device.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;

/**
 * App 网关转发的障碍遥测。
 *
 * <p>对应手杖上行文本报文 {@code <状态>,<距离cm>}。App 解析后拆成结构化字段，
 * 因此这里两个字段都可能缺省 —— 校验规则是「至少给一个」，这条跨字段约束
 * 用注解表达不了，放在 Service 层判断并抛 104008。
 *
 * <p>量程上限取 2000cm：HC-SR04 标称量程 2-400cm，但固件在超量程时可能回传
 * 一个放大的毛刺值；2000 是个足够宽松的哨兵，既能挡住明显的脏数据，
 * 又不会误杀未来的换型（例如换成量程更大的模块）。
 *
 * @param status     固件状态串（CLEAR/NEAR/DANGER），可缺省
 * @param distanceCm 障碍距离（cm），可缺省；与 status 同时出现时以距离为准
 * @param battery    电量百分比，可缺省（当前原型硬件无电量检测）
 * @param rssi       BLE 链路 RSSI（dBm），可缺省
 * @param reportedAtMs App 侧采样时刻（毫秒时间戳），可缺省
 */
public record DeviceTelemetryRequest(

        @Size(max = 10, message = "状态取值长度不能超过 10")
        String status,

        @Min(value = 0, message = "距离不能为负数")
        @Max(value = 2000, message = "距离超出量程（最大 2000cm）")
        Integer distanceCm,

        @Min(value = 0, message = "电量不能为负数")
        @Max(value = 100, message = "电量不能超过 100")
        Integer battery,

        @Min(value = -120, message = "RSSI 不能低于 -120dBm")
        @Max(value = 0, message = "RSSI 不能高于 0dBm")
        Integer rssi,

        Long reportedAtMs
) {
}
