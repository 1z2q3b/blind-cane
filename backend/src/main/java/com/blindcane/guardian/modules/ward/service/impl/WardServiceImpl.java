package com.blindcane.guardian.modules.ward.service.impl;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.blindcane.guardian.common.exception.BizException;
import com.blindcane.guardian.common.result.ErrorCode;
import com.blindcane.guardian.common.util.AesCryptoUtil;
import com.blindcane.guardian.modules.alert.entity.AlertRecord;
import com.blindcane.guardian.modules.alert.mapper.AlertRecordMapper;
import com.blindcane.guardian.modules.device.dto.DeviceVO;
import com.blindcane.guardian.modules.device.entity.Device;
import com.blindcane.guardian.modules.device.mapper.DeviceMapper;
import com.blindcane.guardian.modules.geofence.entity.Geofence;
import com.blindcane.guardian.modules.geofence.mapper.GeofenceMapper;
import com.blindcane.guardian.modules.geofence.service.GeofenceEvaluator;
import com.blindcane.guardian.modules.location.dto.LatestLocation;
import com.blindcane.guardian.modules.location.entity.LocationRecord;
import com.blindcane.guardian.modules.location.mapper.LocationRecordMapper;
import com.blindcane.guardian.modules.location.service.LocationCacheService;
import com.blindcane.guardian.modules.ward.dto.WardCreateRequest;
import com.blindcane.guardian.modules.ward.dto.WardDeleteResultVO;
import com.blindcane.guardian.modules.ward.dto.WardDetailVO;
import com.blindcane.guardian.modules.ward.dto.WardUpdateRequest;
import com.blindcane.guardian.modules.ward.dto.WardVO;
import com.blindcane.guardian.modules.ward.entity.Ward;
import com.blindcane.guardian.modules.ward.entity.WardGuardian;
import com.blindcane.guardian.modules.ward.mapper.WardGuardianMapper;
import com.blindcane.guardian.modules.ward.mapper.WardMapper;
import com.blindcane.guardian.modules.ward.service.GuardianService;
import com.blindcane.guardian.modules.ward.service.WardService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class WardServiceImpl implements WardService {

    private final WardMapper wardMapper;
    private final WardGuardianMapper wardGuardianMapper;
    private final DeviceMapper deviceMapper;
    private final AlertRecordMapper alertRecordMapper;
    private final GuardianService guardianService;
    private final AesCryptoUtil aesCryptoUtil;
    private final LocationCacheService locationCacheService;
    private final GeofenceMapper geofenceMapper;
    private final LocationRecordMapper locationRecordMapper;
    private final GeofenceEvaluator geofenceEvaluator;

    @Override
    @Transactional(rollbackFor = Exception.class)
    public WardDetailVO create(Long userId, WardCreateRequest request) {
        Ward ward = new Ward();
        ward.setName(request.name());
        ward.setRelation(request.relation());
        ward.setBirthYear(request.birthYear());
        ward.setHomeAddress(request.homeAddress());
        ward.setHomeLng(request.homeLng());
        ward.setHomeLat(request.homeLat());
        // 库里是 NOT NULL DEFAULT ''：这里把 null 归一成空串，
        // 避免 MyBatis-Plus 插入时显式写 NULL 触发约束错误
        ward.setContactPhone(request.contactPhone() == null ? "" : request.contactPhone().trim());
        ward.setMedicalNotes(aesCryptoUtil.encrypt(request.medicalNotes()));
        ward.setPrimaryUserId(userId);
        wardMapper.insert(ward);

        // 建档与建关系必须同一事务：否则会出现「档案存在但没人有权限看」的孤儿数据
        WardGuardian relation = new WardGuardian();
        relation.setWardId(ward.getId());
        relation.setUserId(userId);
        relation.setRole(WardGuardian.ROLE_PRIMARY);
        relation.setInviteStatus(WardGuardian.INVITE_ACCEPTED);
        wardGuardianMapper.insert(relation);

        log.info("被监护人档案已创建: wardId={}, 主监护人 userId={}", ward.getId(), userId);
        return toDetail(ward, WardGuardian.ROLE_PRIMARY, null, null, 0L);
    }

    @Override
    public List<WardVO> listMine(Long userId) {
        List<WardGuardian> relations = wardGuardianMapper.selectList(Wrappers.<WardGuardian>lambdaQuery()
                .eq(WardGuardian::getUserId, userId)
                .eq(WardGuardian::getInviteStatus, WardGuardian.INVITE_ACCEPTED));
        if (relations.isEmpty()) {
            return List.of();
        }
        Map<Long, Integer> roleByWard = relations.stream()
                .collect(Collectors.toMap(WardGuardian::getWardId, WardGuardian::getRole, (a, b) -> a));
        List<Long> wardIds = List.copyOf(roleByWard.keySet());

        List<Ward> wards = wardMapper.selectList(Wrappers.<Ward>lambdaQuery().in(Ward::getId, wardIds));

        // 设备：一个被监护人当前最多绑一台，按 wardId 建索引后 O(1) 取
        Map<Long, Device> deviceByWard = deviceMapper.selectList(Wrappers.<Device>lambdaQuery()
                        .in(Device::getWardId, wardIds))
                .stream()
                .collect(Collectors.toMap(Device::getWardId, Function.identity(), (a, b) -> a));

        // 待处理告警数：一次 IN 查询后在内存分组，避免按 wardId 循环查 N 次
        Map<Long, Long> pendingByWard = alertRecordMapper.selectList(Wrappers.<AlertRecord>lambdaQuery()
                        .select(AlertRecord::getWardId)
                        .in(AlertRecord::getWardId, wardIds)
                        .eq(AlertRecord::getStatus, AlertRecord.STATUS_PENDING))
                .stream()
                .collect(Collectors.groupingBy(AlertRecord::getWardId, Collectors.counting()));

        return wards.stream().map(ward -> {
            Long wardId = ward.getId();
            return new WardVO(
                    wardId, ward.getName(), ward.getRelation(), ward.getBirthYear(), ward.getHomeAddress(),
                    ward.getHomeLng(), ward.getHomeLat(), ward.getContactPhone(),
                    roleByWard.get(wardId),
                    DeviceVO.from(deviceByWard.get(wardId)),
                    locationCacheService.get(wardId),
                    pendingByWard.getOrDefault(wardId, 0L));
        }).toList();
    }

    @Override
    public WardDetailVO detail(Long userId, Long wardId) {
        WardGuardian relation = guardianService.requireGuardian(userId, wardId);
        Ward ward = requireWard(wardId);
        return assemble(ward, relation.getRole());
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public WardDetailVO update(Long userId, Long wardId, WardUpdateRequest request) {
        WardGuardian relation = guardianService.requireGuardian(userId, wardId);
        requireWard(wardId);

        // 只 set 非 null 字段：MyBatis-Plus 默认 NOT_NULL 更新策略会跳过 null，
        // 因此这里天然实现了「部分更新」，不需要额外的 patch 判断
        Ward patch = new Ward();
        patch.setId(wardId);
        patch.setName(request.name());
        patch.setRelation(request.relation());
        patch.setBirthYear(request.birthYear());
        patch.setHomeAddress(request.homeAddress());
        // 坐标允许单独更新：家属可能只重新定位而不动文字地址。
        // 传 null 表示不改；想清空坐标目前没有入口（地址被删掉时坐标留着也无害）。
        patch.setHomeLng(request.homeLng());
        patch.setHomeLat(request.homeLat());
        if (request.contactPhone() != null) {
            // 空串是"清空号码"的有效语义，不能在这里过滤掉
            patch.setContactPhone(request.contactPhone().trim());
        }
        if (request.medicalNotes() != null) {
            patch.setMedicalNotes(aesCryptoUtil.encrypt(request.medicalNotes()));
        }
        wardMapper.updateById(patch);

        log.info("被监护人档案已更新: wardId={}, 操作人={}", wardId, userId);
        Ward updated = wardMapper.selectById(wardId);
        return assemble(updated, relation.getRole());
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public WardDeleteResultVO delete(Long userId, Long wardId) {
        WardGuardian relation = guardianService.requireGuardian(userId, wardId);
        // 档案归属权只在主监护人手上：副监护人误删会连带清掉所有轨迹和告警，且不可恢复
        if (!Integer.valueOf(WardGuardian.ROLE_PRIMARY).equals(relation.getRole())) {
            throw BizException.of(ErrorCode.NO_GUARDIAN_PERMISSION, "只有主监护人可以删除该档案");
        }
        requireWard(wardId);

        // 顺序有讲究：先清"挂在档案上的从属数据"，最后删档案本体。
        // 整套动作在一个事务里，任何一步抛异常都会整体回滚，不会出现删一半留一半。

        // 1) 围栏：纯配置，随档案一起消失
        List<Long> fenceIds = geofenceMapper.selectList(Wrappers.<Geofence>lambdaQuery()
                        .select(Geofence::getId)
                        .eq(Geofence::getWardId, wardId))
                .stream()
                .map(Geofence::getId)
                .toList();
        int fences = geofenceMapper.delete(Wrappers.<Geofence>lambdaQuery()
                .eq(Geofence::getWardId, wardId));
        // Redis 里的 IN/OUT 状态与告警抑制锁必须跟着清，否则 key 会一直残留
        fenceIds.forEach(geofenceEvaluator::clearState);

        // 2) 位置流水：单表里数据量最大的一张
        int locations = locationRecordMapper.delete(Wrappers.<LocationRecord>lambdaQuery()
                .eq(LocationRecord::getWardId, wardId));

        // 3) 告警历史
        int alerts = alertRecordMapper.delete(Wrappers.<AlertRecord>lambdaQuery()
                .eq(AlertRecord::getWardId, wardId));

        // 4) 设备只解绑、不删除：手杖是物理硬件，档案没了它还要能绑给下一位老人用。
        //    必须用 UpdateWrapper.set 显式写 null——updateById 的 NOT_NULL 策略会跳过 null 字段，
        //    那样这里会变成"什么都没更新"，设备永远挂在已删除的 ward 上。
        int devices = deviceMapper.update(null, Wrappers.<Device>lambdaUpdate()
                .set(Device::getWardId, null)
                .eq(Device::getWardId, wardId));

        // 5) 监护关系：主监护人和所有副监护人一起解除
        int guardians = wardGuardianMapper.delete(Wrappers.<WardGuardian>lambdaQuery()
                .eq(WardGuardian::getWardId, wardId));

        // 6) 档案本体
        wardMapper.deleteById(wardId);

        log.info("被监护人档案已删除: wardId={}, 操作人={}; 连带清理 围栏={} 轨迹={} 告警={} 解绑设备={} 解除关系={}",
                wardId, userId, fences, locations, alerts, devices, guardians);

        return new WardDeleteResultVO(wardId, fences, locations, alerts, devices, guardians);
    }

    // ------------------------------------------------------------------

    private Ward requireWard(Long wardId) {
        Ward ward = wardMapper.selectById(wardId);
        if (ward == null) {
            throw BizException.of(ErrorCode.WARD_NOT_FOUND);
        }
        return ward;
    }

    /** 详情：解密病史 + 汇总设备 / 位置 / 待处理告警。 */
    private WardDetailVO assemble(Ward ward, Integer myRole) {
        Device device = deviceMapper.selectOne(Wrappers.<Device>lambdaQuery()
                .eq(Device::getWardId, ward.getId())
                .last("LIMIT 1"));
        Long pending = alertRecordMapper.selectCount(Wrappers.<AlertRecord>lambdaQuery()
                .eq(AlertRecord::getWardId, ward.getId())
                .eq(AlertRecord::getStatus, AlertRecord.STATUS_PENDING));
        return toDetail(ward, myRole, device, locationCacheService.get(ward.getId()),
                pending == null ? 0L : pending);
    }

    private WardDetailVO toDetail(Ward ward, Integer myRole, Device device,
                                  LatestLocation location, long pendingCount) {
        return new WardDetailVO(
                ward.getId(), ward.getName(), ward.getRelation(), ward.getBirthYear(),
                ward.getHomeAddress(), ward.getHomeLng(), ward.getHomeLat(), ward.getContactPhone(),
                aesCryptoUtil.decrypt(ward.getMedicalNotes()),
                ward.getPrimaryUserId(), myRole,
                DeviceVO.from(device), location, pendingCount, ward.getCreatedAt());
    }
}
