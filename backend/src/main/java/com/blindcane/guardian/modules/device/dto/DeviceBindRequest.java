package com.blindcane.guardian.modules.device.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/** 绑定导盲杖设备。 */
public record DeviceBindRequest(

        @NotBlank(message = "设备序列号不能为空")
        @Size(max = 50, message = "设备序列号长度不能超过 50")
        String deviceSn,

        @NotNull(message = "被监护人不能为空")
        Long wardId
) {
}
