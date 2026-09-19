package com.blindcane.guardian.common.exception;

import com.blindcane.guardian.common.result.ApiResponse;
import com.blindcane.guardian.common.result.ErrorCode;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.ConstraintViolationException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.validation.BindException;
import org.springframework.validation.FieldError;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.NoHandlerFoundException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

import java.util.stream.Collectors;

/**
 * 全局异常处理：把各类异常统一收敛成 ApiResponse，避免每个 Controller 写 try-catch。
 */
@Slf4j
@RestControllerAdvice
public class GlobalExceptionHandler {

    /** 业务异常：预期内的失败，只打 warn 不带堆栈，避免污染日志。 */
    @ExceptionHandler(BizException.class)
    public ApiResponse<Void> handleBizException(BizException e, HttpServletRequest request) {
        log.warn("业务异常 [{}] {} -> code={}, msg={}",
                request.getMethod(), request.getRequestURI(), e.getErrorCode().getCode(), e.getMessage());
        return ApiResponse.failure(e.getErrorCode(), e.getMessage());
    }

    /** @RequestBody 上的 @Valid 校验失败。 */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ApiResponse<Void> handleMethodArgumentNotValid(MethodArgumentNotValidException e) {
        return ApiResponse.failure(ErrorCode.PARAM_ERROR, extractFieldErrors(e.getBindingResult().getFieldErrors()));
    }

    /** 表单/查询参数绑定校验失败。 */
    @ExceptionHandler(BindException.class)
    public ApiResponse<Void> handleBindException(BindException e) {
        return ApiResponse.failure(ErrorCode.PARAM_ERROR, extractFieldErrors(e.getBindingResult().getFieldErrors()));
    }

    /** 方法参数上的 @Validated 约束（如 @NotBlank 直接标在 Controller 参数上）。 */
    @ExceptionHandler(ConstraintViolationException.class)
    public ApiResponse<Void> handleConstraintViolation(ConstraintViolationException e) {
        String message = e.getConstraintViolations().stream()
                .map(v -> v.getPropertyPath() + " " + v.getMessage())
                .collect(Collectors.joining("；"));
        return ApiResponse.failure(ErrorCode.PARAM_ERROR, message.isEmpty() ? ErrorCode.PARAM_ERROR.getMessage() : message);
    }

    /** 缺少必填参数 / 类型不匹配 / 请求体不是合法 JSON。 */
    @ExceptionHandler({
            MissingServletRequestParameterException.class,
            MethodArgumentTypeMismatchException.class,
            HttpMessageNotReadableException.class
    })
    public ApiResponse<Void> handleBadRequest(Exception e) {
        log.warn("请求参数异常: {}", e.getMessage());
        return ApiResponse.failure(ErrorCode.PARAM_ERROR);
    }

    /**
     * 路径不存在。必须单独处理：Spring 6.1 起「找不到静态资源」会抛
     * NoResourceFoundException，如果不拦就会被下面的兜底分支吞成
     * 「200 + 109002」，前端无法区分「接口写错」和「服务端挂了」。
     */
    @ExceptionHandler({NoResourceFoundException.class, NoHandlerFoundException.class})
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ApiResponse<Void> handleNotFound(Exception e, HttpServletRequest request) {
        log.warn("路径不存在: [{}] {}", request.getMethod(), request.getRequestURI());
        return ApiResponse.failure(ErrorCode.RESOURCE_NOT_FOUND);
    }

    /** 请求方法不支持。返回 405 而不是 200，方便前端联调时一眼看出问题。 */
    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    @ResponseStatus(HttpStatus.METHOD_NOT_ALLOWED)
    public ApiResponse<Void> handleMethodNotSupported(HttpRequestMethodNotSupportedException e) {
        return ApiResponse.failure(ErrorCode.METHOD_NOT_ALLOWED, "请求方法不支持：" + e.getMethod());
    }

    /**
     * 权限不足。这里必须显式处理并重新抛出交给 Spring Security，
     * 否则会被下面的兜底 Exception 分支吞掉，变成 200 + 109002，
     * 前端就无法区分「没登录」和「没权限」。
     */
    @ExceptionHandler(AccessDeniedException.class)
    public void handleAccessDenied(AccessDeniedException e) {
        throw e;
    }

    /** 兜底：非预期异常，必须打完整堆栈，否则线上无法定位。 */
    @ExceptionHandler(Exception.class)
    public ApiResponse<Void> handleException(Exception e, HttpServletRequest request) {
        log.error("系统异常 [{}] {}", request.getMethod(), request.getRequestURI(), e);
        return ApiResponse.failure(ErrorCode.INTERNAL_ERROR);
    }

    private String extractFieldErrors(java.util.List<FieldError> fieldErrors) {
        if (fieldErrors.isEmpty()) {
            return ErrorCode.PARAM_ERROR.getMessage();
        }
        return fieldErrors.stream()
                .map(fe -> fe.getField() + " " + fe.getDefaultMessage())
                .collect(Collectors.joining("；"));
    }
}
