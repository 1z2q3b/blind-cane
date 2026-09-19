package com.blindcane.guardian.framework.websocket;

import com.blindcane.guardian.modules.alert.dto.AlertVO;
import com.blindcane.guardian.modules.alert.entity.AlertRecord;
import com.blindcane.guardian.modules.device.dto.DeviceStatusMessage;
import com.blindcane.guardian.modules.location.dto.LatestLocation;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Component;

/**
 * WebSocket 消息发送工具。
 *
 * <p>把所有 topic 拼接集中在这里，是为了避免 topic 字符串散落在业务代码里 ——
 * 拼错一个字母的后果是「推送静默失效」，前后端都要花很久才能发现。
 * 三个主题与提示词 7.3 一一对应：
 * <pre>
 * /topic/ward/{wardId}/location  位置更新
 * /topic/ward/{wardId}/alert     告警
 * /topic/ward/{wardId}/device    设备状态
 * </pre>
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class WsMessageSender {

    private static final String TOPIC_LOCATION = "/topic/ward/%d/location";
    private static final String TOPIC_ALERT = "/topic/ward/%d/alert";
    private static final String TOPIC_DEVICE = "/topic/ward/%d/device";

    private final SimpMessagingTemplate messagingTemplate;

    public static String locationTopic(Long wardId) {
        return String.format(TOPIC_LOCATION, wardId);
    }

    public static String alertTopic(Long wardId) {
        return String.format(TOPIC_ALERT, wardId);
    }

    public static String deviceTopic(Long wardId) {
        return String.format(TOPIC_DEVICE, wardId);
    }

    public void sendLocation(Long wardId, LatestLocation location) {
        send(locationTopic(wardId), location, "位置");
    }

    public void sendAlert(AlertRecord alert) {
        if (alert.getWardId() == null) {
            return;
        }
        // 推送载荷刻意用 AlertVO 而不是实体：
        // 1) 与 REST /alerts 的返回结构完全一致，App 端只需要一个模型一套解析；
        // 2) 实体里的 updatedAt / pendingConfirm 等内部字段不会外泄；
        // 3) wardName 传 null —— 客户端是按 ward 主题订阅的，本来就知道 wardId 对应谁。
        send(alertTopic(alert.getWardId()), AlertVO.from(alert, null), "告警");
    }

    public void sendDeviceStatus(Long wardId, DeviceStatusMessage status) {
        if (wardId == null) {
            return;
        }
        send(deviceTopic(wardId), status, "设备状态");
    }

    private void send(String destination, Object payload, String what) {
        try {
            messagingTemplate.convertAndSend(destination, payload);
            log.debug("已推送{} -> {}", what, destination);
        } catch (Exception e) {
            // 推送失败不影响主链路：告警已落库，位置已进 Redis / 队列，客户端可轮询兜底
            log.error("推送{}失败 destination={}", what, destination, e);
        }
    }
}
