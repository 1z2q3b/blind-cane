package com.blindcane.guardian.modules.device.service;

import com.blindcane.guardian.modules.device.dto.BleAddressRequest;
import com.blindcane.guardian.modules.device.dto.DeviceBindRequest;
import com.blindcane.guardian.modules.device.dto.DeviceReport;
import com.blindcane.guardian.modules.device.dto.DeviceVO;
import com.blindcane.guardian.modules.device.entity.Device;

import java.time.LocalDateTime;

/** 设备绑定与状态服务。 */
public interface DeviceService {

    /** 通过 SN 码绑定设备到被监护人（可同时登记蓝牙地址与自定义名称）。 */
    DeviceVO bind(Long userId, DeviceBindRequest request);

    /** 解绑设备（保留设备档案，仅解除归属，并清空 BLE 运行时状态）。 */
    void unbind(Long userId, Long deviceId);

    /** 设备状态（电量/信号/在线/最后上报时间/蓝牙链路/障碍状态/播报模式）。 */
    DeviceVO status(Long userId, Long deviceId);

    /**
     * 设备上报入口：更新在线状态、电量、信号、BLE 链路与障碍遥测，
     * 并维护告警相关的两类副作用（重置离线去抖标记、检查低电量阶梯）。
     * S3 的位置上报、S4 的电量衰减、BLE 遥测都走这里。
     */
    void recordReport(DeviceReport report);

    /**
     * 旧的四参数形态，等价于 {@code recordReport(DeviceReport.of(...))}。
     *
     * @deprecated 新代码请用 {@link #recordReport(DeviceReport)}；
     *             保留只为不改动已通过验证的存量调用点
     */
    @Deprecated
    default void recordReport(Long deviceId, Integer battery, Integer signalLevel,
                              LocalDateTime reportedAt) {
        recordReport(DeviceReport.of(deviceId, battery, signalLevel, reportedAt));
    }

    /**
     * 登记 / 刷新手杖蓝牙地址。
     *
     * <p>换手机后必须重新登记：iOS 给外设分配的 UUID 是随机的，
     * 不刷新则自动重连永远匹配不上。
     *
     * @throws com.blindcane.guardian.common.exception.BizException 104006（地址已被他人占用）
     */
    DeviceVO bindBleAddress(Long userId, Long deviceId, BleAddressRequest request);

    /**
     * 清空 BLE 运行时状态：链路标记、RSSI、障碍状态/距离/时间、静音模式。
     *
     * <p>解绑与 Mock 复位都会调用。不清的话，下一个使用者一绑定就会看到
     * 上一任留下的「危险 12cm」「已静音」—— 那是另一根手杖的状态。
     */
    void clearBleState(Long deviceId);

    /**
     * 取一台「当前家属有权访问」的设备，供位置 / 告警等模块复用权限判断。
     *
     * @throws com.blindcane.guardian.common.exception.BizException 104003 / 103001
     */
    Device requireAccessibleDevice(Long userId, Long deviceId);
}
