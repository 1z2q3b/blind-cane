package com.blindcane.guardian.modules.alert.notifier;

import com.blindcane.guardian.modules.alert.entity.AlertRecord;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * 日志分发通道：S2 阶段的唯一通道，把告警打到控制台便于联调。
 *
 * <p>S3 接入 WebSocket 后这个通道仍然保留 —— 它是排查「告警到底有没有产生」
 * 最快的手段，比翻数据库省事。
 */
@Slf4j
@Component
public class LoggingAlertNotifier implements AlertNotifier {

    @Override
    public void notify(AlertRecord alert) {
        if (alert.getSeverity() != null && alert.getSeverity() == 1) {
            log.warn("【高优告警】id={} 类型={} 被监护人={} 位置=({}, {}) 时间={}",
                    alert.getId(), alert.getAlertType(), alert.getWardId(),
                    alert.getLng(), alert.getLat(), alert.getCreatedAt());
        } else {
            log.info("【告警】id={} 类型={} 级别={} 被监护人={} 时间={}",
                    alert.getId(), alert.getAlertType(), alert.getSeverity(),
                    alert.getWardId(), alert.getCreatedAt());
        }
    }

    @Override
    public String channelName() {
        return "LOG";
    }
}
