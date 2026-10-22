package com.blindcane.guardian.modules.location.dto;

import lombok.Data;

import java.time.LocalDateTime;

/**
 * 轨迹查询的数据库行（内部使用，不直接返回给 App）。
 *
 * <p>为什么不用 record：MyBatis 把 {@code @Select} 结果映射到对象时走的是
 * setter/构造器自动映射，record 需要显式构造器映射配置，容易在版本升级时踩坑。
 * 这里用可变 POJO 最稳，转成对外的 {@link TrackPointVO} 再交给调用方。
 */
@Data
public class TrackRow {

    /** 纬度。注意：数据库里存的是 POINT(纬度 经度)，所以 ST_X 取到的是纬度。 */
    private Double lat;

    /** 经度。ST_Y 取到的是经度。 */
    private Double lng;

    private Float speed;

    private Float accuracyM;

    private LocalDateTime reportedAt;
}
