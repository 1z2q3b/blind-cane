package com.blindcane.guardian.modules.alert.service.impl;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.blindcane.guardian.modules.alert.dto.AlertCreateCommand;
import com.blindcane.guardian.modules.alert.entity.AlertRecord;
import com.blindcane.guardian.modules.alert.entity.AlertType;
import com.blindcane.guardian.modules.alert.mapper.AlertRecordMapper;
import com.blindcane.guardian.modules.alert.notifier.AlertNotifier;
import com.blindcane.guardian.modules.alert.service.AlertService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
public class AlertServiceImpl implements AlertService {

    /** 疑似跌倒的初始级别：警示（不触发全屏强提醒）。 */
    public static final int SUSPECT_SEVERITY = 2;
    /** 升级后的级别：紧急（App 全屏强提醒）。 */
    public static final int ESCALATED_SEVERITY = 1;

    private final AlertRecordMapper alertRecordMapper;
    /** Spring 会把所有 AlertNotifier 实现都注入进来；没有实现时注入空列表而非报错。 */
    private final List<AlertNotifier> notifiers;

    @Override
    @Transactional(rollbackFor = Exception.class)
    public AlertRecord create(AlertCreateCommand command) {
        AlertRecord alert = new AlertRecord();
        alert.setWardId(command.wardId());
        alert.setDeviceId(command.deviceId());
        alert.setAlertType(command.type().name());
        // severity 允许调用方覆盖，否则用类型默认级别
        alert.setSeverity(command.severity() == null
                ? command.type().getSeverity()
                : command.severity());
        alert.setLng(command.lng());
        alert.setLat(command.lat());
        alert.setAddress(command.address());
        alert.setNote(command.note());
        alert.setStatus(AlertRecord.STATUS_PENDING);
        alert.setPendingConfirm(command.pendingConfirm()
                ? AlertRecord.CONFIRM_PENDING
                : AlertRecord.CONFIRM_DONE);

        alertRecordMapper.insert(alert);
        log.info("告警已落库: id={}, wardId={}, type={}, severity={}, pendingConfirm={}",
                alert.getId(), alert.getWardId(), alert.getAlertType(),
                alert.getSeverity(), alert.getPendingConfirm());

        // 分发必须等事务提交后再做：否则家属收到推送立刻回查告警详情时，
        // 可能因为事务未提交而查不到记录，表现为「收到告警但列表里没有」。
        afterCommit(() -> dispatch(alert));
        return alert;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public List<AlertRecord> escalatePendingFalls(int timeoutSeconds) {
        LocalDateTime deadline = LocalDateTime.now().minusSeconds(timeoutSeconds);
        List<AlertRecord> suspects = alertRecordMapper.selectList(Wrappers.<AlertRecord>lambdaQuery()
                .eq(AlertRecord::getAlertType, AlertType.FALL_DETECTED.name())
                .eq(AlertRecord::getPendingConfirm, AlertRecord.CONFIRM_PENDING)
                .eq(AlertRecord::getStatus, AlertRecord.STATUS_PENDING)
                .lt(AlertRecord::getCreatedAt, deadline));

        if (suspects.isEmpty()) {
            return List.of();
        }

        List<AlertRecord> escalated = new ArrayList<>(suspects.size());
        for (AlertRecord suspect : suspects) {
            AlertRecord patch = new AlertRecord();
            patch.setId(suspect.getId());
            patch.setPendingConfirm(AlertRecord.CONFIRM_DONE);
            patch.setSeverity(ESCALATED_SEVERITY);
            patch.setNote(appendNote(suspect.getNote(),
                    "疑似跌倒超过 " + timeoutSeconds + " 秒未确认，已升级为紧急告警"));
            alertRecordMapper.updateById(patch);

            // 用更新后的快照去分发；直接复用查出来的对象会推送旧的 severity/pendingConfirm，
            // App 收到后仍然按「警示」渲染，升级就白做了
            suspect.setPendingConfirm(AlertRecord.CONFIRM_DONE);
            suspect.setSeverity(ESCALATED_SEVERITY);
            suspect.setNote(patch.getNote());
            escalated.add(suspect);

            log.warn("疑似跌倒升级为紧急告警: alertId={}, wardId={}, 创建于={}",
                    suspect.getId(), suspect.getWardId(), suspect.getCreatedAt());
            afterCommit(() -> dispatch(suspect));
        }
        return escalated;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public AlertRecord cancelPendingFall(Long alertId, String note) {
        AlertRecord alert = alertRecordMapper.selectById(alertId);
        if (alert == null) {
            return null;
        }
        // 幂等：已经取消过 / 已经升级过的告警不再重复处理，
        // 避免杖体连按两下把「已升级的紧急告警」又改回误报
        if (alert.getPendingConfirm() == null
                || alert.getPendingConfirm() != AlertRecord.CONFIRM_PENDING) {
            return null;
        }

        AlertRecord patch = new AlertRecord();
        patch.setId(alertId);
        patch.setPendingConfirm(AlertRecord.CONFIRM_DONE);
        patch.setStatus(AlertRecord.STATUS_FALSE_ALARM);
        patch.setHandledAt(LocalDateTime.now());
        patch.setNote(appendNote(alert.getNote(),
                note == null || note.isBlank() ? "用户按键取消，判定为误报" : note));
        alertRecordMapper.updateById(patch);

        alert.setPendingConfirm(AlertRecord.CONFIRM_DONE);
        alert.setStatus(AlertRecord.STATUS_FALSE_ALARM);
        alert.setHandledAt(patch.getHandledAt());
        alert.setNote(patch.getNote());

        log.info("疑似跌倒已取消: alertId={}, wardId={}", alertId, alert.getWardId());
        // 也要推送：App 端可能已经弹出了确认倒计时条，需要一条消息把它撤掉
        afterCommit(() -> dispatch(alert));
        return alert;
    }

    // ------------------------------------------------------------------

    private String appendNote(String origin, String extra) {
        if (origin == null || origin.isBlank()) {
            return extra;
        }
        return origin + "；" + extra;
    }

    private void dispatch(AlertRecord alert) {
        for (AlertNotifier notifier : notifiers) {
            try {
                notifier.notify(alert);
            } catch (Exception e) {
                // 单个通道失败不影响其他通道，更不影响已落库的告警
                log.error("告警分发失败 channel={}, alertId={}", notifier.channelName(), alert.getId(), e);
            }
        }
    }

    private void afterCommit(Runnable task) {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    task.run();
                }
            });
        } else {
            task.run();
        }
    }
}
