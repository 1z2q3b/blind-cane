package com.blindcane.guardian.modules.alert.service;

import com.blindcane.guardian.common.result.PageResult;
import com.blindcane.guardian.modules.alert.dto.AlertHandleRequest;
import com.blindcane.guardian.modules.alert.dto.AlertVO;
import com.blindcane.guardian.modules.alert.dto.PendingCountVO;

/**
 * 告警中心（家属端消费侧）。
 *
 * <p>与 {@link AlertService} 分开的理由：一个是内部生产入口
 * （设备/定时任务调用，只需 create），一个是面向 App 的查询与处理接口，
 * 两者的鉴权要求、调用方、变更频率都不同，混在一个类里会越来越难维护。
 */
public interface AlertCenterService {

    /**
     * 告警历史（分页 + 筛选）。
     *
     * @param wardId 为空时查该家属名下全部被监护人的告警
     * @param type   告警类型，可为空
     * @param status 处理状态，可为空
     */
    PageResult<AlertVO> query(Long userId, Long wardId, String type, Integer status, long page, long size);

    /** 待处理数量（首页角标）。 */
    PendingCountVO pendingCount(Long userId);

    /** 处理告警：标记已处理 / 误报。 */
    AlertVO handle(Long userId, Long alertId, AlertHandleRequest request);

    /** 告警详情。 */
    AlertVO detail(Long userId, Long alertId);
}
