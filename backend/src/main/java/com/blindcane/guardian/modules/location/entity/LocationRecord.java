package com.blindcane.guardian.modules.location.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 位置记录（location_record）。
 *
 * <p>注意 {@code pointWkt} 字段：数据库里 location 是 POINT SRID 4326 空间列，
 * MyBatis-Plus 无法直接映射，所以走自定义 SQL 用
 * {@code ST_GeomFromText(#{pointWkt}, 4326)} 写入。
 * 该字段标了 exist=false，不参与 ORM 映射。
 */
@Data
@TableName("location_record")
public class LocationRecord {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Long wardId;

    private Long deviceId;

    private Float accuracyM;

    private Float speed;

    private LocalDateTime reportedAt;

    /**
     * WKT 文本，注意两点：
     * 1) 顺序是 {@code POINT(纬度 经度)} —— MySQL 对 SRID 4326 采用 EPSG 定义的
     *    latitude-longitude 轴序，与「经度在前」的常见直觉相反；
     * 2) 仅用于写入，读取时请用 {@code ST_Latitude()} / {@code ST_Longitude()} 取值。
     */
    @TableField(exist = false)
    private String pointWkt;

    /**
     * 落库重试次数（内存态，不落库）。
     *
     * <p>用于给重试设上限：如果是 SQL 写法错误这类「必然失败」的问题，
     * 无上限重试只会每 5 秒刷一条错误日志并且永远不成功。
     */
    @TableField(exist = false)
    private int retryCount;
}
