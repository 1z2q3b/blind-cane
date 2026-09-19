package com.blindcane.guardian.modules.ward.dto;

import com.blindcane.guardian.modules.device.dto.DeviceVO;
import com.blindcane.guardian.modules.location.dto.LatestLocation;

/**
 * 被监护人列表项（首页卡片）。
 *
 * <p>刻意不含 medicalNotes：列表接口不应该解密并返回病史，
 * 那是详情页（且只有确认过监护权限后）才需要的数据。
 *
 * @param myRole           当前家属在该被监护人上的角色（1 主 / 2 副），前端据此决定是否显示「邀请家属」
 * @param device           绑定设备状态，未绑定为 null
 * @param latestLocation   最新位置（Redis 热数据），无上报为 null
 * @param pendingAlertCount 待处理告警数，用于首页红角标
 */
public record WardVO(Long id, String name, String relation, Integer birthYear,
                     String homeAddress, Integer myRole,
                     DeviceVO device, LatestLocation latestLocation,
                     long pendingAlertCount) {
}
