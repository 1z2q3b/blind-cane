package com.blindcane.guardian.modules.device.dto;

/**
 * 设备状态变化消息（STOMP {@code /topic/ward/{wardId}/device} 的载荷，对应提示词 7.3）。
 *
 * <p>刻意只带三个字段：家属端首页只关心「有没有掉线、还有多少电、信号好不好」，
 * 传整个 DeviceVO 会把 name / firmwareVersion 等静态信息反复推给客户端。
 */
public record DeviceStatusMessage(Boolean online, Integer battery, Integer signalLevel) {
}
