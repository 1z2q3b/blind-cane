package com.blindcane.guardian.framework.websocket;

/**
 * 监护权限校验接口（框架层定义，领域层实现）。
 *
 * <p>为什么不在拦截器里直接注入 ward 模块的 GuardianService：
 * 那会让 framework 反向依赖 modules，框架层就再也抽不出去了。
 * 定义一个窄接口，由 ward 模块提供适配实现，依赖方向保持 modules → framework。
 */
public interface GuardianPermissionChecker {

    /** 该家属是否对被监护人有（已接受的）监护关系。 */
    boolean hasPermission(Long userId, Long wardId);
}
