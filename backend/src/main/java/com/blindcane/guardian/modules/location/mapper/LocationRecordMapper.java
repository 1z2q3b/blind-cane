package com.blindcane.guardian.modules.location.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.blindcane.guardian.modules.location.entity.LocationRecord;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

import java.util.List;

/** 位置记录 Mapper。 */
@Mapper
public interface LocationRecordMapper extends BaseMapper<LocationRecord> {

    /**
     * 批量插入位置点。
     *
     * <p>为什么不用 BaseMapper.insert：location 列是 POINT SRID 4326 空间类型，
     * JDBC 没有对应类型，必须用 ST_GeomFromText 转换。
     *
     * <p>为什么要批量：10 秒一条上报 × N 台设备，逐条 INSERT 会把写放大到
     * 「每条一次网络往返 + 一次事务」。攒批后一次往返写完，MySQL 只承担
     * 历史轨迹存储，不参与实时查询。
     *
     * <p>注意：SQL 字符串必须以 {@code <script>} 开头，MyBatis 的
     * XMLLanguageDriver 是按字面量判断前缀的，前面多一个换行就会退化成普通 SQL，
     * 导致 foreach 标签被当成 SQL 文本发出去。所以这里刻意不用 Java 文本块。
     */
    @Insert("<script>"
            + "INSERT INTO location_record "
            + "(ward_id, device_id, location, accuracy_m, speed, reported_at, created_at, updated_at) "
            + "VALUES "
            + "<foreach collection='list' item='it' separator=','>"
            + "(#{it.wardId}, #{it.deviceId}, ST_GeomFromText(#{it.pointWkt}, 4326), "
            + "#{it.accuracyM}, #{it.speed}, #{it.reportedAt}, NOW(), NOW())"
            + "</foreach>"
            + "</script>")
    int batchInsert(@Param("list") List<LocationRecord> list);
}
