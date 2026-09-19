package com.blindcane.guardian.modules.device.entity;

import com.baomidou.mybatisplus.annotation.FieldFill;
import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/** 导盲杖设备（device）。 */
@Data
@TableName("device")
public class Device {

    public static final int OFFLINE = 0;
    public static final int ONLINE = 1;

    /** 离线告警已发出 / 未发出。 */
    public static final int OFFLINE_NOTIFIED_YES = 1;
    public static final int OFFLINE_NOTIFIED_NO = 0;

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 设备序列号，家属绑定设备时输入。 */
    private String deviceSn;

    private String name;

    /** 当前绑定被监护人，NULL = 未绑定。 */
    private Long wardId;

    private Integer battery;

    /** 信号强度 1-4。 */
    private Integer signalLevel;

    /** 0 离线 / 1 在线。 */
    private Integer online;

    private LocalDateTime lastOnlineAt;

    private String firmwareVersion;

    /**
     * 离线告警去抖标记：同一离线周期只发一次 DEVICE_OFFLINE。
     * 设备恢复上报后会被重置为 0，这样下一次掉线才能再次告警。
     */
    private Integer offlineNotified;

    @TableField(fill = FieldFill.INSERT)
    private LocalDateTime createdAt;

    @TableField(fill = FieldFill.INSERT_UPDATE)
    private LocalDateTime updatedAt;
}
