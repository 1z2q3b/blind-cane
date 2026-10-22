package com.blindcane.guardian.modules.ward.service;

import com.blindcane.guardian.modules.ward.dto.WardCreateRequest;
import com.blindcane.guardian.modules.ward.dto.WardDeleteResultVO;
import com.blindcane.guardian.modules.ward.dto.WardDetailVO;
import com.blindcane.guardian.modules.ward.dto.WardUpdateRequest;
import com.blindcane.guardian.modules.ward.dto.WardVO;

import java.util.List;

/** 被监护人档案服务。 */
public interface WardService {

    /** 创建档案，并把创建者登记为主监护人。 */
    WardDetailVO create(Long userId, WardCreateRequest request);

    /** 我的被监护人列表（含设备状态、最新位置摘要、待处理告警数）。 */
    List<WardVO> listMine(Long userId);

    WardDetailVO detail(Long userId, Long wardId);

    WardDetailVO update(Long userId, Long wardId, WardUpdateRequest request);

    /**
     * 删除档案，并连带清理该档案产生的所有从属数据。
     *
     * <p>只有主监护人可以删除。设备会被解绑而不是删除。
     */
    WardDeleteResultVO delete(Long userId, Long wardId);
}
