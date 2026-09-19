package com.blindcane.guardian.modules.alert.task;

import com.blindcane.guardian.framework.config.BlindcaneProperties;
import com.blindcane.guardian.modules.alert.entity.AlertRecord;
import com.blindcane.guardian.modules.alert.service.AlertService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * 疑似跌倒超时升级（提示词 5.8）。
 *
 * <p>跌倒检测天生误报率高（放下手杖、坐下、颠簸都可能触发）。如果一检测到就全屏强提醒，
 * 家属两天就会被骚扰到关掉通知 —— 那才是真正的安全风险。所以流程设计成两段：
 * <ol>
 *   <li>刚检测到 → 建立 severity=2 的「疑似」告警，家属端显示为警示 + 确认倒计时条；</li>
 *   <li>杖体 30 秒内按键取消 → 标记误报，推送一条撤销消息；</li>
 *   <li>30 秒没动静 → 本任务把它升级成 severity=1 的紧急告警并重新推送，
 *       家属端此时才弹全屏强提醒（含一键拨号）。</li>
 * </ol>
 *
 * <p>扫描周期刻意取 5 秒而不是 30 秒：如果用 30 秒周期，实际升级时刻会在
 * 30~60 秒之间漂移，演示时"30 秒升级"这个卖点就对不上了。周期越短漂移越小，
 * 5 秒 × 一次全表索引扫描的成本可以忽略。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class FallConfirmScanTask {

    private final AlertService alertService;
    private final BlindcaneProperties properties;

    @Scheduled(fixedDelay = 5_000, initialDelay = 10_000)
    public void scan() {
        int timeoutSeconds = properties.getSimulator().getFallConfirmTimeoutSeconds();
        List<AlertRecord> escalated = alertService.escalatePendingFalls(timeoutSeconds);
        if (!escalated.isEmpty()) {
            log.warn("本轮共升级 {} 条疑似跌倒告警（超时 {} 秒未确认）", escalated.size(), timeoutSeconds);
        }
    }
}
