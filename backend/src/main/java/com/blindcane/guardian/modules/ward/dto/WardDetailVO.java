package com.blindcane.guardian.modules.ward.dto;

import com.blindcane.guardian.modules.device.dto.DeviceVO;
import com.blindcane.guardian.modules.location.dto.LatestLocation;

import java.time.LocalDateTime;

/**
 * 被监护人详情。
 *
 * <p>与列表项的区别：这里会返回解密后的 medicalNotes。
 * 因此这个 VO 只允许在监护权限校验通过之后构造。
 */
public record WardDetailVO(Long id, String name, String relation, Integer birthYear,
                           String homeAddress, Double homeLng, Double homeLat, String contactPhone,
                           String medicalNotes,
                           Long primaryUserId, Integer myRole,
                           DeviceVO device, LatestLocation latestLocation,
                           long pendingAlertCount, LocalDateTime createdAt) {
}
