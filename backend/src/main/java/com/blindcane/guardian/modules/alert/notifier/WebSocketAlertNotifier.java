package com.blindcane.guardian.modules.alert.notifier;

import com.blindcane.guardian.framework.websocket.WsMessageSender;
import com.blindcane.guardian.modules.alert.entity.AlertRecord;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * WebSocket 分发通道：把告警推到 {@code /topic/ward/{wardId}/alert}，
 * 在线家属端收到后立即弹全屏强提醒（铃声 + 震动）。
 *
 * <p>在线走 WebSocket 的好处是端到端延迟在百毫秒级，能轻松满足
 * 「SOS 3 秒内到达」的验收标准；离线家属由后续的极光推送通道兜底。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class WebSocketAlertNotifier implements AlertNotifier {

    private final WsMessageSender wsMessageSender;

    @Override
    public void notify(AlertRecord alert) {
        wsMessageSender.sendAlert(alert);
    }

    @Override
    public String channelName() {
        return "WEBSOCKET";
    }
}
