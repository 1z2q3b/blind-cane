package com.blindcane.guardian.modules.ward.service.impl;

import com.blindcane.guardian.framework.websocket.GuardianPermissionChecker;
import com.blindcane.guardian.modules.ward.service.GuardianService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/** 把 ward 模块的监护关系查询适配给框架层的 WebSocket 拦截器使用。 */
@Component
@RequiredArgsConstructor
public class GuardianPermissionCheckerAdapter implements GuardianPermissionChecker {

    private final GuardianService guardianService;

    @Override
    public boolean hasPermission(Long userId, Long wardId) {
        // 注意这里用 isGuardian 而不是 requireGuardian：
        // 拦截器需要的是布尔判断，让它去捕获业务异常来控制订阅流程属于滥用异常。
        return guardianService.isGuardian(userId, wardId);
    }
}
