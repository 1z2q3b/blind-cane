package com.blindcane.guardian.modules.ward.service;

import com.blindcane.guardian.modules.ward.entity.WardGuardian;

import java.util.List;

/**
 * 监护关系查询与鉴权。
 *
 * <p>独立成一个服务而不是塞进 WardService：device / location / alert 模块都要用它，
 * 如果放在 WardService 里会形成循环依赖（WardService 又需要设备信息）。
 */
public interface GuardianService {

    /**
     * 校验家属对被监护人有监护权限，返回监护关系。
     *
     * @throws com.blindcane.guardian.common.exception.BizException 103001 无监护权限
     */
    WardGuardian requireGuardian(Long userId, Long wardId);

    /** 是否（已接受的）监护人关系。 */
    boolean isGuardian(Long userId, Long wardId);

    /** 当前家属负责的全部被监护人 id。 */
    List<Long> listWardIds(Long userId);
}
