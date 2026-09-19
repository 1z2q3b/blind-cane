package com.blindcane.guardian.modules.alert.dto;

/**
 * 待处理告警数量（首页角标）。
 *
 * @param total  该家属名下所有被监护人的待处理告警总数，用于 App 底部 tab 红点
 * @param byWard 分被监护人明细，用于每张卡的独立角标
 */
public record PendingCountVO(long total, java.util.Map<Long, Long> byWard) {
}
