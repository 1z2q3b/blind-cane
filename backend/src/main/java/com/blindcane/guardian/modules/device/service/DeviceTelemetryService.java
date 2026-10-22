package com.blindcane.guardian.modules.device.service;

import com.blindcane.guardian.modules.device.dto.BleLinkRequest;
import com.blindcane.guardian.modules.device.dto.DeviceTelemetryRequest;
import com.blindcane.guardian.modules.device.dto.DeviceVO;
import com.blindcane.guardian.modules.device.dto.TelemetryAck;

/**
 * BLE 遥测上行通道。
 *
 * <p>与 {@code DeviceService} 分开的理由：后者管的是设备的「身份与归属」
 * （绑定/解绑/状态查询），是产品级的领域服务；本接口管的是「手机网关
 * 转发的实时数据流」，是接入层的关注点。两者生命周期不同 ——
 * 真实硬件换型（例如从 BLE 换成 4G 直连）时，本接口整个会被替换，
 * 而绑定关系那一套不受影响。
 */
public interface DeviceTelemetryService {

    /**
     * 处理一帧障碍遥测。
     *
     * <p>内部做三件事：距离优先的状态判定、节流、链路活性确认。
     *
     * @param userId  当前登录家属，作为鉴权依据
     * @param deviceId 设备主键
     * @return 回执；{@code accepted=false} 表示被节流丢弃
     * @throws com.blindcane.guardian.common.exception.BizException 104008（报文无可用信息）
     */
    TelemetryAck reportTelemetry(Long userId, Long deviceId, DeviceTelemetryRequest request);

    /**
     * 处理蓝牙链路连/断事件；状态变化时向 ward 主题广播一次设备状态。
     */
    DeviceVO updateBleLink(Long userId, Long deviceId, BleLinkRequest request);
}
