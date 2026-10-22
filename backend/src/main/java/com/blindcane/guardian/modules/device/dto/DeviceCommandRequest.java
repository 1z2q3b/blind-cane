package com.blindcane.guardian.modules.device.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 下发命令请求体。
 *
 * <p>长度上限 8 只是防御性的粗筛（挡掉把整段文本塞进来的请求）；
 * 真正的合法性判定是 {@code CaneCommand} 白名单 —— 不在名单里一律 104007。
 *
 * @param command 命令码，目前仅支持 {@code M}
 */
public record DeviceCommandRequest(

        @NotBlank(message = "命令不能为空")
        @Size(max = 8, message = "命令长度不能超过 8")
        String command
) {
}
