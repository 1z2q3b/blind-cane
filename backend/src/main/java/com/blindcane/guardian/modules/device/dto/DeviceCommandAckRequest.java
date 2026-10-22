package com.blindcane.guardian.modules.device.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 命令执行回执。<b>这是设备状态的唯一提交点。</b>
 *
 * <p>整条命令链路上「写 RX 特征」是唯一可能失败的一步：手机可能刚走到门外、
 * 蓝牙信号衰减到写超时，也可能特征不支持写。如果后端在
 * {@code /command} 下发时就把 {@code mute_mode} 翻转，那么一次失败的下发
 * 会让云端与手杖永久失步 —— 家属端显示「已静音」，而手杖还在响。
 *
 * <p>所以约定：{@code /command} 只广播、不改状态；只有 App 确认字节真的写进
 * RX 特征后回调本接口，{@code success=true} 才提交变更。
 * {@code success=false} 时状态保持不变，但服务端仍会广播一次权威状态，
 * 用来纠正客户端在等待期间可能已经做出的乐观显示。
 *
 * @param command 命令码，需与下发时一致
 * @param success 写入 RX 特征是否成功
 * @param detail  失败原因（成功时可为空），会原样写进日志便于排障
 */
public record DeviceCommandAckRequest(

        @NotBlank(message = "命令不能为空")
        @Size(max = 8, message = "命令长度不能超过 8")
        String command,

        boolean success,

        @Size(max = 200, message = "详情长度不能超过 200")
        String detail
) {
}
