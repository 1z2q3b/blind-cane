package com.blindcane.guardian.modules.device.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * 登记 / 刷新手杖蓝牙地址。
 *
 * <p>存在这个接口的根本原因是 iOS 的隐私策略：CoreBluetooth 不暴露外设的真实 MAC，
 * 而是给每台手机 + 每个 App 分配一个随机 UUID，且换手机就变。所以
 * {@code ble_address} 永远只是「就近自动重连的提示」，设备的权威身份是 SN ——
 * 家属换机后必须重新登记一次地址，否则自动重连永远匹配不上。
 *
 * <p>两种格式都接受：
 * <ul>
 *   <li>MAC（Android）：{@code D0:CF:13:8A:00:01}</li>
 *   <li>UUID（iOS）：{@code 8B4C1D2E-3F45-4A6B-9C7D-1E2F3A4B5C6D}</li>
 * </ul>
 */
public record BleAddressRequest(

        @NotBlank(message = "蓝牙地址不能为空")
        @Size(max = 32, message = "蓝牙地址长度不能超过 32")
        @Pattern(regexp = "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$"
                + "|^[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}$",
                message = "蓝牙地址格式不正确（应为 MAC 或 UUID 形式）")
        String bleAddress
) {
}
