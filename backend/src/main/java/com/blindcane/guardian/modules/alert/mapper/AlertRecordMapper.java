package com.blindcane.guardian.modules.alert.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.blindcane.guardian.modules.alert.entity.AlertRecord;
import org.apache.ibatis.annotations.Mapper;

/** 告警记录 Mapper。 */
@Mapper
public interface AlertRecordMapper extends BaseMapper<AlertRecord> {
}
