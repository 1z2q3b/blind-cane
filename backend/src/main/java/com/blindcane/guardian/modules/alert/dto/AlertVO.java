package com.blindcane.guardian.modules.alert.dto;

import com.blindcane.guardian.modules.alert.entity.AlertRecord;

import java.time.LocalDateTime;

/**
 * 告警视图（列表、详情、WebSocket 推送共用同一形态）。
 *
 * <p>前后端共用同一个结构是有意为之：App 端「告警中心列表项」与
 * 「全屏强提醒页」展示的是同一份数据，多定义一套推送专用 DTO 只会让
 * 两端多一份需要同步维护的映射代码。
 *
 * @param wardName 被监护人姓名，列表里显示「张老先生 · 跌倒」比只显示 wardId 友好得多
 * @param statusText 状态中文文案，避免前端再维护一份枚举映射
 */
public record AlertVO(Long id, Long wardId, String wardName, Long deviceId,
                      String alertType, Integer severity, String severityText,
                      Double lng, Double lat, String address,
                      Integer status, String statusText,
                      Long handlerUserId, LocalDateTime handledAt, String note,
                      Integer pendingConfirm, LocalDateTime createdAt) {

    public static AlertVO from(AlertRecord alert, String wardName) {
        return new AlertVO(
                alert.getId(), alert.getWardId(), wardName, alert.getDeviceId(),
                alert.getAlertType(), alert.getSeverity(), severityText(alert.getSeverity()),
                alert.getLng(), alert.getLat(), alert.getAddress(),
                alert.getStatus(), statusText(alert.getStatus()),
                alert.getHandlerUserId(), alert.getHandledAt(), alert.getNote(),
                alert.getPendingConfirm(), alert.getCreatedAt());
    }

    private static String severityText(Integer severity) {
        if (severity == null) {
            return "";
        }
        return switch (severity) {
            case 1 -> "紧急";
            case 2 -> "警示";
            default -> "提示";
        };
    }

    private static String statusText(Integer status) {
        if (status == null) {
            return "";
        }
        return switch (status) {
            case AlertRecord.STATUS_RESOLVED -> "已处理";
            case AlertRecord.STATUS_FALSE_ALARM -> "误报";
            default -> "待处理";
        };
    }
}
