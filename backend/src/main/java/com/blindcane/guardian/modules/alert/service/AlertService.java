package com.blindcane.guardian.modules.alert.service;

import com.blindcane.guardian.modules.alert.dto.AlertCreateCommand;
import com.blindcane.guardian.modules.alert.entity.AlertRecord;

import java.util.List;

/** 告警产生服务。所有告警（SOS/跌倒/低电量/离线/围栏）都必须经由此入口，保证分发链路统一。 */
public interface AlertService {

    /**
     * 创建告警：先落库拿到 id，再分发。
     *
     * <p>顺序不可颠倒 —— 分发（WebSocket / 推送）都可能失败，
     * 先落库才能保证告警永远不丢，App 端还能靠轮询兜底补上。
     *
     * @return 已落库的告警记录（含自增 id 与 createdAt）
     */
    AlertRecord create(AlertCreateCommand command);

    /**
     * 扫描「疑似待确认」的跌倒告警，把超时未确认的升级为紧急告警并重新分发。
     *
     * <p>对应提示词 5.8 的「30 秒倒计时」：跌倒检测算法误报率高，用户容易被骚扰到
     * 直接关掉告警权限。折中方案是先发一条「警示」级别的疑似告警给家属，
     * 同时给杖体 30 秒按键取消窗口；超时仍未取消，才升级成「紧急」全屏强提醒。
     *
     * @param timeoutSeconds 确认窗口时长
     * @return 本次升级的告警列表（空列表表示无需升级）
     */
    List<AlertRecord> escalatePendingFalls(int timeoutSeconds);

    /**
     * 杖体按键取消疑似跌倒（或家属手动标记误报）。
     *
     * @return 取消后的告警；告警不存在 / 已不是待确认状态时返回 null
     */
    AlertRecord cancelPendingFall(Long alertId, String note);
}
