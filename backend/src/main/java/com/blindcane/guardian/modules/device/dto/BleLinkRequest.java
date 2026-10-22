package com.blindcane.guardian.modules.device.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;

/**
 * 蓝牙链路状态上报（连接 / 断开各调一次）。
 *
 * <p>为什么断连不能靠「遥测超时」推断，而要 App 显式上报：
 * 断连是瞬时事件，而超时判定至少滞后一个节流窗口（1 秒）加上网络往返。
 * 在这段滞后期里，云端仍持有断开前最后一帧的 {@code DANGER,12}，
 * 家属端会把它当成「此刻正前方 12cm 有障碍」显示出来 ——
 * 一个已过期的高危状态停留在屏幕上，比不显示更危险。
 *
 * <p>{@code connected=false} 时 {@code rssi} 必须为空：此时链路已经没了，
 * 任何 RSSI 读数都是无意义的残留值。
 *
 * @param connected 链路是否已建立
 * @param rssi      BLE 链路 RSSI（dBm），仅在 connected=true 时有意义
 */
public record BleLinkRequest(

        boolean connected,

        @Min(value = -120, message = "RSSI 不能低于 -120dBm")
        @Max(value = 0, message = "RSSI 不能高于 0dBm")
        Integer rssi
) {
}
