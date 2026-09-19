package com.blindcane.guardian.common.result;

import lombok.Getter;

/**
 * 统一响应结构（提示词 7.1）。
 *
 * <pre>
 * { "code": 0, "message": "成功", "data": {}, "timestamp": 1750000000000 }
 * </pre>
 *
 * <p>业务结果一律看 {@code code}，HTTP 状态码只用于表达「认证/授权层」的结论：
 * 业务异常（参数错误、无监护权限、SN 不存在等）返回 HTTP 200 + 非 0 code；
 * 认证失败返回 401 + 101003、授权不足返回 403 + 103001。
 *
 * <p>这样 App 端拦截器的分工就非常清晰：HTTP 401 触发「静默刷新令牌」，
 * 其余全部走 code 映射中文文案，不需要在两个回调里写重复判断。
 */
@Getter
public class ApiResponse<T> {

    private final int code;
    private final String message;
    private final T data;
    private final long timestamp;

    private ApiResponse(int code, String message, T data) {
        this.code = code;
        this.message = message;
        this.data = data;
        this.timestamp = System.currentTimeMillis();
    }

    public static <T> ApiResponse<T> success() {
        return new ApiResponse<>(ErrorCode.SUCCESS.getCode(), ErrorCode.SUCCESS.getMessage(), null);
    }

    public static <T> ApiResponse<T> success(T data) {
        return new ApiResponse<>(ErrorCode.SUCCESS.getCode(), ErrorCode.SUCCESS.getMessage(), data);
    }

    public static <T> ApiResponse<T> success(String message, T data) {
        return new ApiResponse<>(ErrorCode.SUCCESS.getCode(), message, data);
    }

    public static <T> ApiResponse<T> failure(ErrorCode errorCode) {
        return new ApiResponse<>(errorCode.getCode(), errorCode.getMessage(), null);
    }

    /** 用自定义文案覆盖枚举默认文案（例如校验失败时回传具体字段错误）。 */
    public static <T> ApiResponse<T> failure(ErrorCode errorCode, String message) {
        return new ApiResponse<>(errorCode.getCode(), message, null);
    }

    public static <T> ApiResponse<T> failure(int code, String message) {
        return new ApiResponse<>(code, message, null);
    }
}
