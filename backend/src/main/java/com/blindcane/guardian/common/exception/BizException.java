package com.blindcane.guardian.common.exception;

import com.blindcane.guardian.common.result.ErrorCode;
import lombok.Getter;

/**
 * 业务异常。抛出后由 {@link GlobalExceptionHandler} 统一转换为 ApiResponse。
 *
 * <p>不继承受检异常：业务失败是「正常的分支」，用受检异常会污染每一层方法签名。
 */
@Getter
public class BizException extends RuntimeException {

    private final ErrorCode errorCode;

    public BizException(ErrorCode errorCode) {
        super(errorCode.getMessage());
        this.errorCode = errorCode;
    }

    /** 用更具体的文案覆盖枚举默认值，例如「SN 不存在」时回带用户输入的 SN。 */
    public BizException(ErrorCode errorCode, String message) {
        super(message);
        this.errorCode = errorCode;
    }

    public static BizException of(ErrorCode errorCode) {
        return new BizException(errorCode);
    }

    public static BizException of(ErrorCode errorCode, String message) {
        return new BizException(errorCode, message);
    }

    /** 断言为真，否则抛出业务异常。用于替代满屏的 if-throw。 */
    public static void assertTrue(boolean condition, ErrorCode errorCode) {
        if (!condition) {
            throw new BizException(errorCode);
        }
    }

    public static void assertTrue(boolean condition, ErrorCode errorCode, String message) {
        if (!condition) {
            throw new BizException(errorCode, message);
        }
    }
}
