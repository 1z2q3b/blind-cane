package com.blindcane.guardian.modules.device.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.blindcane.guardian.modules.device.entity.Device;
import org.apache.ibatis.annotations.Mapper;

/** 设备 Mapper。 */
@Mapper
public interface DeviceMapper extends BaseMapper<Device> {
}
