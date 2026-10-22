package com.blindcane.guardian.modules.geofence.entity;

import com.baomidou.mybatisplus.annotation.FieldFill;
import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 电子围栏（geofence）。
 *
 * <p>只做圆形围栏（中心点 + 半径）。理由：手杖上报频率是秒级、围栏数量是个位数，
 * 圆形判定只要一次 haversine 距离计算，比多边形射线法简单一个量级；
 * 而家属实际画围栏时（"以家为中心 500 米"）几乎都是圆形需求。
 * 多边形留到真有需求再加，表结构可以靠新增 type 字段平滑扩展。
 *
 * <p>两种语义靠 {@link #fenceType} 区分，触发方向相反：
 * <ul>
 *   <li>安全区：**离开**时告警（老人走出日常活动范围）；</li>
 *   <li>危险区：**进入**时告警（老人走进河边/工地）。</li>
 * </ul>
 */
@Data
@TableName("geofence")
public class Geofence {

    /** 安全区：离开触发 GEOFENCE_EXIT。 */
    public static final int TYPE_SAFE = 1;
    /** 危险区：进入触发 GEOFENCE_ENTER。 */
    public static final int TYPE_DANGER = 2;

    public static final int ENABLED = 1;
    public static final int DISABLED = 0;

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 归属被监护人 ward.id。 */
    private Long wardId;

    private String name;

    private Double centerLng;

    private Double centerLat;

    /** 半径（米）。 */
    private Integer radiusM;

    /** 1 安全区 / 2 危险区。 */
    private Integer fenceType;

    /** 启用开关：0 关 / 1 开。停用的围栏不参与命中判定。 */
    private Integer enabled;

    @TableField(fill = FieldFill.INSERT)
    private LocalDateTime createdAt;

    @TableField(fill = FieldFill.INSERT_UPDATE)
    private LocalDateTime updatedAt;

    // 注意：这里不要再手写 isEnabled()。
    // Lombok 已经为 enabled 生成了 getEnabled()，再补一个返回 boolean 的 isEnabled()
    // 会让「enabled」属性出现两个类型不同的 getter，MyBatis 反射时直接抛
    // Illegal overloaded getter method with ambiguous type，导致所有 insert / update 失败
    // （表现就是接口一律返回 109002，而查询一切正常，极难从日志以外的地方看出来）。
    // 需要判断是否启用时，内联写成 enabled != null && enabled == ENABLED 即可。
}
