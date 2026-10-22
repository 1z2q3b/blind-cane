package com.blindcane.guardian.modules.geofence.service.impl;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.blindcane.guardian.common.exception.BizException;
import com.blindcane.guardian.common.result.ErrorCode;
import com.blindcane.guardian.modules.geofence.dto.GeofenceCreateRequest;
import com.blindcane.guardian.modules.geofence.dto.GeofenceUpdateRequest;
import com.blindcane.guardian.modules.geofence.dto.GeofenceVO;
import com.blindcane.guardian.modules.geofence.entity.Geofence;
import com.blindcane.guardian.modules.geofence.mapper.GeofenceMapper;
import com.blindcane.guardian.modules.geofence.service.GeofenceService;
import com.blindcane.guardian.modules.ward.service.GuardianService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
public class GeofenceServiceImpl implements GeofenceService {

    private final GeofenceMapper geofenceMapper;
    private final GuardianService guardianService;

    @Override
    public List<GeofenceVO> list(Long userId, Long wardId) {
        guardianService.requireGuardian(userId, wardId);
        return geofenceMapper.selectList(Wrappers.<Geofence>lambdaQuery()
                        .eq(Geofence::getWardId, wardId)
                        // 新建的排前面：家属刚加完围栏就想看到它，而不是翻到列表底部
                        .orderByDesc(Geofence::getId))
                .stream()
                .map(GeofenceVO::from)
                .toList();
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public GeofenceVO create(Long userId, GeofenceCreateRequest request) {
        guardianService.requireGuardian(userId, request.wardId());

        Geofence entity = new Geofence();
        entity.setWardId(request.wardId());
        entity.setName(request.name().trim());
        entity.setCenterLng(request.centerLng());
        entity.setCenterLat(request.centerLat());
        entity.setRadiusM(request.radiusM());
        entity.setFenceType(request.fenceType());
        // 不传就默认启用：家属点"保存"时的预期就是它立刻生效
        entity.setEnabled(request.enabled() == null ? Geofence.ENABLED : request.enabled());
        geofenceMapper.insert(entity);

        log.info("围栏已创建: id={}, wardId={}, name={}, type={}, 中心=({}, {}), 半径={}m",
                entity.getId(), entity.getWardId(), entity.getName(), entity.getFenceType(),
                entity.getCenterLng(), entity.getCenterLat(), entity.getRadiusM());
        return GeofenceVO.from(entity);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public GeofenceVO update(Long userId, Long id, GeofenceUpdateRequest request) {
        Geofence existing = requireExisting(userId, id);

        // 只把非 null 字段塞进 patch 对象，updateById 会自动跳过 null，
        // 于是天然就是"改哪传哪"的局部更新
        Geofence patch = new Geofence();
        patch.setId(id);
        if (request.name() != null) {
            if (!StringUtils.hasText(request.name())) {
                throw BizException.of(ErrorCode.PARAM_ERROR, "围栏名称不能为空白");
            }
            patch.setName(request.name().trim());
        }
        patch.setCenterLng(request.centerLng());
        patch.setCenterLat(request.centerLat());
        patch.setRadiusM(request.radiusM());
        patch.setFenceType(request.fenceType());
        patch.setEnabled(request.enabled());
        geofenceMapper.updateById(patch);

        // 坐标或半径变了，紧跟着的第一次判定会拿旧状态做比较，可能立刻误报一次。
        // 这里不主动清 Redis 状态：判定器本身对"状态缺失"是静默初始化，
        // 留着旧状态反而能在"围栏从 500m 缩到 100m"时正确触发一次离开告警。
        log.info("围栏已修改: id={}, wardId={}", id, existing.getWardId());

        return GeofenceVO.from(geofenceMapper.selectById(id));
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void delete(Long userId, Long id) {
        Geofence existing = requireExisting(userId, id);
        geofenceMapper.deleteById(id);
        log.info("围栏已删除: id={}, wardId={}, name={}", id, existing.getWardId(), existing.getName());
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public GeofenceVO setEnabled(Long userId, Long id, int enabled) {
        requireExisting(userId, id);
        Geofence patch = new Geofence();
        patch.setId(id);
        patch.setEnabled(enabled);
        geofenceMapper.updateById(patch);
        log.info("围栏启停已变更: id={}, enabled={}", id, enabled);
        return GeofenceVO.from(geofenceMapper.selectById(id));
    }

    @Override
    public List<Geofence> listEnabledByWard(Long wardId) {
        return geofenceMapper.selectList(Wrappers.<Geofence>lambdaQuery()
                .eq(Geofence::getWardId, wardId)
                .eq(Geofence::getEnabled, Geofence.ENABLED));
    }

    // ------------------------------------------------------------------

    /** 取出围栏并校验当前家属对它有监护权限；不存在报 109003，无权限报 103001。 */
    private Geofence requireExisting(Long userId, Long id) {
        Geofence existing = geofenceMapper.selectById(id);
        if (existing == null) {
            throw BizException.of(ErrorCode.RESOURCE_NOT_FOUND, "围栏不存在");
        }
        guardianService.requireGuardian(userId, existing.getWardId());
        return existing;
    }
}
