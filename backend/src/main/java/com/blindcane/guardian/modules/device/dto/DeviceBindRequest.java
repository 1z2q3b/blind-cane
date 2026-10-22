package com.blindcane.guardian.modules.device.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * 绑定导盲杖设备。
 *
 * <p>绑定时可以顺便把刚刚扫到的手杖蓝牙地址一起提交 —— 这是 App 里
 * 「扫描 → 选中 → 绑定」这一条主流程的自然形态：用户在扫描列表里点的那一项
 * 本来就带着地址，此时不提交就得再让用户去设置页手动登记一次。
 *
 * <p>{@code bleAddress} 的校验正则里保留了「空串」分支：表单里这个字段可选，
 * Flutter 的 TextFormField 未填写时提交的是 {@code ""} 而不是 {@code null}，
 * 若不加 {@code ^$} 就会把一次正常的空值提交判成格式错误。
 */
public record DeviceBindRequest(

        @NotBlank(message = "设备序列号不能为空")
        @Size(max = 50, message = "设备序列号长度不能超过 50")
        String deviceSn,

        @NotNull(message = "被监护人不能为空")
        Long wardId,

        /** 可选：手杖蓝牙地址（Android=MAC / iOS=随机 UUID）。 */
        @Size(max = 32, message = "蓝牙地址长度不能超过 32")
        @Pattern(regexp = "^$|^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$"
                + "|^[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}$",
                message = "蓝牙地址格式不正确（应为 MAC 或 UUID 形式）")
        String bleAddress,

        /** 可选：自定义设备名；留空则用「<被监护人姓名>的导盲杖」。 */
        @Size(max = 50, message = "设备名称长度不能超过 50")
        String name
) {
}
