package com.blindcane.guardian.modules.ward.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.blindcane.guardian.modules.ward.entity.Ward;
import org.apache.ibatis.annotations.Mapper;

/** 被监护人档案 Mapper。 */
@Mapper
public interface WardMapper extends BaseMapper<Ward> {
}
