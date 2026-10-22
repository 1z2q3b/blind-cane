package com.blindcane.guardian.modules.location.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.blindcane.guardian.modules.location.dto.TrackRow;
import com.blindcane.guardian.modules.location.entity.LocationRecord;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.time.LocalDateTime;
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

    /**
     * 按时间段查历史轨迹。
     *
     * <p><b>轴序陷阱（务必别改）</b>：入库时写的是 {@code POINT(纬度 经度)}
     * （见 LocationServiceImpl#toRecord 的说明，MySQL 对 SRID 4326 严格按
     * EPSG:4326 的 latitude-longitude 轴序解析），所以这里
     * {@code ST_X} 取出来的是**纬度**、{@code ST_Y} 取的是**经度**，
     * 与"X=经度、Y=纬度"的日常直觉正好相反。写反的话地图上的点会跑到
     * 几千公里外（纬度 113 直接越界），非常好排查但很容易写错。
     *
     * <p>用 {@code reported_at >= start AND < end} 而不是 BETWEEN：
     * 时间段是左闭右开，相邻两天不会重复统计同一秒的数据。
     *
     * <p>LIMIT 由调用方控制，先粗查再用等距抽样降采样，
     * 避免一次把几十万条点位全部塞进内存和网络。
     */
    @Select("SELECT ST_X(location) AS lat, ST_Y(location) AS lng, "
            + "speed, accuracy_m AS accuracyM, reported_at AS reportedAt "
            + "FROM location_record "
            + "WHERE ward_id = #{wardId} AND reported_at >= #{start} AND reported_at < #{end} "
            + "ORDER BY reported_at "
            + "LIMIT #{limit}")
    List<TrackRow> selectTrack(@Param("wardId") Long wardId,
                               @Param("start") LocalDateTime start,
                               @Param("end") LocalDateTime end,
                               @Param("limit") int limit);
}
