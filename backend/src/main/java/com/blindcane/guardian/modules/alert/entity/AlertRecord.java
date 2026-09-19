package com.blindcane.guardian.modules.alert.entity;

import com.baomidou.mybatisplus.annotation.FieldFill;
import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/** 告警记录（alert_record）。 */
@Data
@TableName("alert_record")
public class AlertRecord {

    /** status：待处理。 */
    public static final int STATUS_PENDING = 0;
    /** status：已处理。 */
    public static final int STATUS_RESOLVED = 1;
    /** status：误报。 */
    public static final int STATUS_FALSE_ALARM = 2;

    /** pendingConfirm：已是定稿事件，不再等待确认。 */
    public static final int CONFIRM_DONE = 0;
    /** pendingConfirm：疑似事件，等待杖体按键确认（超时自动升级）。 */
    public static final int CONFIRM_PENDING = 1;

    @TableId(type = IdType.AUTO)
    private Long id;

    private Long wardId;

    private Long deviceId;

    private String alertType;

    /** 1 高 / 2 中 / 3 低。 */
    private Integer severity;

    private Double lng;

    private Double lat;

    /** 逆地理编码文案，无 Key 时为空。 */
    private String address;

    /** 0 待处理 / 1 已处理 / 2 误报。 */
    private Integer status;

    private Long handlerUserId;

    private LocalDateTime handledAt;

    private String note;

    /** 1 = 疑似待确认（跌倒 30 秒升级用）。 */
    private Integer pendingConfirm;

    @TableField(fill = FieldFill.INSERT)
    private LocalDateTime createdAt;

    @TableField(fill = FieldFill.INSERT_UPDATE)
    private LocalDateTime updatedAt;
}
