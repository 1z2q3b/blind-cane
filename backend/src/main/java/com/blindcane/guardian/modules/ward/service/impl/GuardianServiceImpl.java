package com.blindcane.guardian.modules.ward.service.impl;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.blindcane.guardian.common.exception.BizException;
import com.blindcane.guardian.common.result.ErrorCode;
import com.blindcane.guardian.modules.ward.entity.WardGuardian;
import com.blindcane.guardian.modules.ward.mapper.WardGuardianMapper;
import com.blindcane.guardian.modules.ward.service.GuardianService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
@RequiredArgsConstructor
public class GuardianServiceImpl implements GuardianService {

    private final WardGuardianMapper wardGuardianMapper;

    @Override
    public WardGuardian requireGuardian(Long userId, Long wardId) {
        WardGuardian relation = wardGuardianMapper.selectOne(Wrappers.<WardGuardian>lambdaQuery()
                .eq(WardGuardian::getWardId, wardId)
                .eq(WardGuardian::getUserId, userId)
                .eq(WardGuardian::getInviteStatus, WardGuardian.INVITE_ACCEPTED)
                .last("LIMIT 1"));
        if (relation == null) {
            // 统一报「无监护权限」而不是「被监护人不存在」：
            // 否则可以通过错误码差异探测出系统里有哪些被监护人 id，属于信息泄露。
            throw BizException.of(ErrorCode.NO_GUARDIAN_PERMISSION);
        }
        return relation;
    }

    @Override
    public boolean isGuardian(Long userId, Long wardId) {
        return wardGuardianMapper.selectCount(Wrappers.<WardGuardian>lambdaQuery()
                .eq(WardGuardian::getWardId, wardId)
                .eq(WardGuardian::getUserId, userId)
                .eq(WardGuardian::getInviteStatus, WardGuardian.INVITE_ACCEPTED)) > 0;
    }

    @Override
    public List<Long> listWardIds(Long userId) {
        return wardGuardianMapper.selectList(Wrappers.<WardGuardian>lambdaQuery()
                        .select(WardGuardian::getWardId)
                        .eq(WardGuardian::getUserId, userId)
                        .eq(WardGuardian::getInviteStatus, WardGuardian.INVITE_ACCEPTED))
                .stream()
                .map(WardGuardian::getWardId)
                .distinct()
                .toList();
    }
}
