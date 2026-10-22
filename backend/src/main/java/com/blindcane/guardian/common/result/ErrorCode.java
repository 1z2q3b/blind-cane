package com.blindcane.guardian.common.result;

import lombok.Getter;

/**
 * 六位错误码枚举。
 *
 * <p>编码规则（提示词 7.1）：前 3 位模块码 + 后 3 位错误序号。
 * <ul>
 *   <li>101xxx 认证</li>
 *   <li>103xxx 被监护人 / 监护关系</li>
 *   <li>104xxx 设备</li>
 *   <li>106xxx 告警</li>
 *   <li>109xxx 系统通用</li>
 * </ul>
 *
 * <p>这样分段的收益：App 端拦截器可以直接按前 3 位做通用处理
 * （例如 101 段统一跳登录页），后 3 位再映射到具体中文提示，
 * 不需要在后端加任何额外字段。
 */
@Getter
public enum ErrorCode {

    /** 成功。按约定 code = 0。 */
    SUCCESS(0, "成功"),

    // ---------- 101xxx 认证 ----------
    SMS_CODE_ERROR(101001, "验证码错误"),
    SMS_CODE_EXPIRED(101002, "验证码已过期，请重新获取"),
    TOKEN_INVALID(101003, "登录状态无效或已过期，请重新登录"),
    REFRESH_TOKEN_INVALID(101004, "刷新令牌无效或已过期，请重新登录"),
    SMS_SEND_TOO_FREQUENT(101005, "验证码发送过于频繁，请稍后再试"),
    ACCOUNT_DISABLED(101006, "账号已被禁用，请联系客服"),
    PHONE_FORMAT_ERROR(101007, "手机号格式不正确"),
    SMS_DAILY_LIMIT(101008, "今日验证码发送次数已达上限"),
    SMS_SERVICE_UNAVAILABLE(101009, "验证码服务暂时不可用，请稍后再试"),
    PHONE_ALREADY_REGISTERED(101010, "该手机号已注册，请直接登录"),
    ACCOUNT_NOT_FOUND(101011, "账号不存在，请先注册"),
    PASSWORD_ERROR(101012, "手机号或密码错误"),
    PASSWORD_NOT_SET(101013, "该账号未设置密码，请使用验证码登录"),
    LOGIN_METHOD_REQUIRED(101014, "请选择验证码登录或密码登录"),

    // ---------- 103xxx 被监护人 / 监护关系 ----------
    NO_GUARDIAN_PERMISSION(103001, "无监护权限"),
    WARD_NOT_FOUND(103002, "被监护人不存在"),
    GUARDIAN_ALREADY_EXISTS(103003, "该家属已是副监护人"),
    CANNOT_REMOVE_PRIMARY(103004, "主监护人不能被移除"),

    // ---------- 104xxx 设备 ----------
    DEVICE_SN_NOT_FOUND(104001, "设备序列号不存在，请核对后重试"),
    DEVICE_ALREADY_BOUND(104002, "该设备已被绑定"),
    DEVICE_NOT_FOUND(104003, "设备不存在"),
    DEVICE_NOT_BOUND(104004, "该设备尚未绑定被监护人"),
    DEVICE_WARD_OCCUPIED(104005, "该被监护人已绑定其他设备，请先解绑"),
    /** BLE：蓝牙地址被另一台仍在绑定的设备占用（尽力而为的冲突检测，见 BleAddressRequest 说明）。 */
    DEVICE_BLE_ADDRESS_OCCUPIED(104006, "该手杖已绑定到其他被监护人，请先解绑"),
    /** BLE：命令不在白名单内（如固件未实现的预留命令）。 */
    DEVICE_COMMAND_UNSUPPORTED(104007, "不支持的命令"),
    /** BLE：遥测报文既没有可用状态也没有距离，无法判断。 */
    DEVICE_TELEMETRY_INVALID(104008, "上报数据不完整：状态与距离至少需要其一"),

    // ---------- 106xxx 告警 ----------
    ALERT_NOT_FOUND(106001, "告警记录不存在"),
    ALERT_ALREADY_HANDLED(106002, "该告警已被处理"),
    ALERT_HANDLE_RESULT_INVALID(106003, "处理结果只能是 RESOLVED 或 FALSE_ALARM"),

    // ---------- 109xxx 系统通用 ----------
    PARAM_ERROR(109001, "参数错误"),
    INTERNAL_ERROR(109002, "服务器内部错误，请稍后重试"),
    RESOURCE_NOT_FOUND(109003, "请求的资源不存在"),
    METHOD_NOT_ALLOWED(109004, "请求方法不被支持"),
    ;

    private final int code;
    private final String message;

    ErrorCode(int code, String message) {
        this.code = code;
        this.message = message;
    }
}
