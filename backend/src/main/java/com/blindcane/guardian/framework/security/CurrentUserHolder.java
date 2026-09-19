package com.blindcane.guardian.framework.security;

import com.blindcane.guardian.common.exception.BizException;
import com.blindcane.guardian.common.result.ErrorCode;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

/**
 * 从 SecurityContext 读取当前登录用户的工具。
 *
 * <p>刻意不封装成 @AuthenticationPrincipal 参数注入：告警分发、离线检测这类
 * 由定时任务/异步线程触发的逻辑没有请求上下文，静态方法更好用。
 */
public final class CurrentUserHolder {

    private CurrentUserHolder() {
    }

    /** 取当前用户，未登录直接抛 101003（由全局异常处理转成统一响应）。 */
    public static LoginUser require() {
        LoginUser user = getOrNull();
        if (user == null) {
            throw BizException.of(ErrorCode.TOKEN_INVALID);
        }
        return user;
    }

    public static Long requireUserId() {
        return require().userId();
    }

    /** 取当前用户，允许为空（用于可选登录场景）。 */
    public static LoginUser getOrNull() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated()) {
            return null;
        }
        Object principal = authentication.getPrincipal();
        return principal instanceof LoginUser loginUser ? loginUser : null;
    }
}
