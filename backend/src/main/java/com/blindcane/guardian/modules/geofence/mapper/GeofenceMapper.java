package com.blindcane.guardian.modules.geofence.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.blindcane.guardian.modules.geofence.entity.Geofence;
import org.apache.ibatis.annotations.Mapper;

/** 电子围栏 Mapper。围栏数量很少、条件简单，用 BaseMapper + LambdaQuery 足够，不需要手写 SQL。 */
@Mapper
public interface GeofenceMapper extends BaseMapper<Geofence> {
}
