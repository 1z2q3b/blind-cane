package com.blindcane.guardian.modules.device.service;

import com.blindcane.guardian.modules.device.dto.DeviceBindRequest;
import com.blindcane.guardian.modules.device.dto.DeviceVO;
import com.blindcane.guardian.modules.device.entity.Device;

import java.time.LocalDateTime;

/** 设备绑定与状态服务。 */
public interface DeviceService {

    /** 通过 SN 码绑定设备到被监护人。 */
    DeviceVO bind(Long userId, DeviceBindRequest request);

    /** 解绑设备（保留设备档案，仅解除归属）。 */
    void unbind(Long userId, Long deviceId);

    /** 设备状态（电量/信号/在线/最后上报时间）。 */
    DeviceVO status(Long userId, Long deviceId);

    /**
     * 设备上报入口：更新在线状态、电量、信号，并维护告警相关的两类副作用
     * （重置离线去抖标记、检查低电量阶梯）。S3 的位置上报与 S4 的电量衰减都走这里。
     */
    void recordReport(Long deviceId, Integer battery, Integer signalLevel, LocalDateTime reportedAt);

    /**
     * 取一台「当前家属有权访问」的设备，供位置 / 告警等模块复用权限判断。
     *
     * @throws com.blindcane.guardian.common.exception.BizException 104003 / 103001
     */
    Device requireAccessibleDevice(Long userId, Long deviceId);
}
