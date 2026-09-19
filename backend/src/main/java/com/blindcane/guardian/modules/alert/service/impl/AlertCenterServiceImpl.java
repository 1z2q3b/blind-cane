package com.blindcane.guardian.modules.alert.service.impl;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.blindcane.guardian.common.exception.BizException;
import com.blindcane.guardian.common.result.ErrorCode;
import com.blindcane.guardian.common.result.PageResult;
import com.blindcane.guardian.modules.alert.dto.AlertHandleRequest;
import com.blindcane.guardian.modules.alert.dto.AlertVO;
import com.blindcane.guardian.modules.alert.dto.PendingCountVO;
import com.blindcane.guardian.modules.alert.entity.AlertRecord;
import com.blindcane.guardian.modules.alert.mapper.AlertRecordMapper;
import com.blindcane.guardian.modules.alert.service.AlertCenterService;
import com.blindcane.guardian.modules.ward.entity.Ward;
import com.blindcane.guardian.modules.ward.mapper.WardMapper;
import com.blindcane.guardian.modules.ward.service.GuardianService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class AlertCenterServiceImpl implements AlertCenterService {

    private static final String RESULT_RESOLVED = "RESOLVED";
    private static final String RESULT_FALSE_ALARM = "FALSE_ALARM";

    private final AlertRecordMapper alertRecordMapper;
    private final WardMapper wardMapper;
    private final GuardianService guardianService;

    @Override
    public PageResult<AlertVO> query(Long userId, Long wardId, String type, Integer status, long page, long size) {
        // 传了 wardId 就必须校验权限，没传则收敛到「我名下的全部被监护人」
        List<Long> wardIds;
        if (wardId != null) {
            guardianService.requireGuardian(userId, wardId);
            wardIds = List.of(wardId);
        } else {
            wardIds = guardianService.listWardIds(userId);
        }
        if (wardIds.isEmpty()) {
            return PageResult.empty(page, size);
        }

        IPage<AlertRecord> pageRequest = new Page<>(page, size);
        IPage<AlertRecord> result = alertRecordMapper.selectPage(pageRequest,
                Wrappers.<AlertRecord>lambdaQuery()
                        .in(AlertRecord::getWardId, wardIds)
                        .eq(type != null && !type.isBlank(), AlertRecord::getAlertType, type)
                        .eq(status != null, AlertRecord::getStatus, status)
                        // 二级排序用 id：同一毫秒产生的多条告警（例如离线+低电量同时触发）
                        // 才有稳定的顺序，否则翻页会出现重复或漏项
                        .orderByDesc(AlertRecord::getCreatedAt)
                        .orderByDesc(AlertRecord::getId));

        Map<Long, String> wardNameMap = loadWardNames(result.getRecords().stream()
                .map(AlertRecord::getWardId).distinct().toList());

        return PageResult.of(
                result.getRecords().stream()
                        .map(record -> AlertVO.from(record, wardNameMap.get(record.getWardId())))
                        .toList(),
                result.getTotal(), result.getCurrent(), result.getSize());
    }

    @Override
    public PendingCountVO pendingCount(Long userId) {
        List<Long> wardIds = guardianService.listWardIds(userId);
        if (wardIds.isEmpty()) {
            return new PendingCountVO(0L, Map.of());
        }
        Map<Long, Long> byWard = alertRecordMapper.selectList(Wrappers.<AlertRecord>lambdaQuery()
                        .select(AlertRecord::getWardId)
                        .in(AlertRecord::getWardId, wardIds)
                        .eq(AlertRecord::getStatus, AlertRecord.STATUS_PENDING))
                .stream()
                .collect(Collectors.groupingBy(AlertRecord::getWardId, Collectors.counting()));
        long total = byWard.values().stream().mapToLong(Long::longValue).sum();
        return new PendingCountVO(total, byWard);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public AlertVO handle(Long userId, Long alertId, AlertHandleRequest request) {
        AlertRecord alert = requireAccessibleAlert(userId, alertId);
        if (alert.getStatus() != null && alert.getStatus() != AlertRecord.STATUS_PENDING) {
            throw BizException.of(ErrorCode.ALERT_ALREADY_HANDLED);
        }

        int newStatus = RESULT_FALSE_ALARM.equals(request.result())
                ? AlertRecord.STATUS_FALSE_ALARM
                : AlertRecord.STATUS_RESOLVED;

        // 用 UpdateWrapper 而不是改实体后 updateById：
        // 这里要同时更新状态、处理人、处理时间和备注，显式列出待更新字段更不容易漏
        AlertRecord patch = new AlertRecord();
        patch.setId(alertId);
        patch.setStatus(newStatus);
        patch.setHandlerUserId(userId);
        patch.setHandledAt(LocalDateTime.now());
        patch.setNote(request.note());
        // pendingConfirm 落定为已确认，避免「标记误报后又被 30 秒升级任务翻出来」
        patch.setPendingConfirm(AlertRecord.CONFIRM_DONE);
        alertRecordMapper.updateById(patch);

        log.info("告警已处理: alertId={}, 结果={}, 处理人={}", alertId, newStatus == AlertRecord.STATUS_FALSE_ALARM
                ? RESULT_FALSE_ALARM : RESULT_RESOLVED, userId);

        AlertRecord updated = alertRecordMapper.selectById(alertId);
        return AlertVO.from(updated, loadWardNames(List.of(updated.getWardId())).get(updated.getWardId()));
    }

    @Override
    public AlertVO detail(Long userId, Long alertId) {
        AlertRecord alert = requireAccessibleAlert(userId, alertId);
        return AlertVO.from(alert, loadWardNames(List.of(alert.getWardId())).get(alert.getWardId()));
    }

    // ------------------------------------------------------------------

    /**
     * 取一条「当前家属有权处理」的告警。
     *
     * <p>先查告警再校验所属被监护人是否有监护关系 —— 不能只靠 wardId 判断，
     * 否则知道 alertId 就能越权读取别人的告警内容和位置。
     */
    private AlertRecord requireAccessibleAlert(Long userId, Long alertId) {
        AlertRecord alert = alertRecordMapper.selectById(alertId);
        if (alert == null) {
            throw BizException.of(ErrorCode.ALERT_NOT_FOUND);
        }
        guardianService.requireGuardian(userId, alert.getWardId());
        return alert;
    }

    private Map<Long, String> loadWardNames(List<Long> wardIds) {
        if (wardIds.isEmpty()) {
            return Map.of();
        }
        return wardMapper.selectList(Wrappers.<Ward>lambdaQuery()
                        .select(Ward::getId, Ward::getName)
                        .in(Ward::getId, wardIds))
                .stream()
                .collect(Collectors.toMap(Ward::getId, Ward::getName, (a, b) -> a, LinkedHashMap::new));
    }
}
