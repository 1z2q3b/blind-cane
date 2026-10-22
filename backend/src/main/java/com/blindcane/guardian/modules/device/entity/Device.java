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

    /** 手杖播报模式：0 工作（语音播报） / 1 静音。取值与下行命令 M 的切换结果同步。 */
    public static final int MUTE_OFF = 0;
    public static final int MUTE_ON = 1;

    /** 手机网关与手杖的 BLE 链路状态。 */
    public static final int BLE_DISCONNECTED = 0;
    public static final int BLE_CONNECTED = 1;

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

    // ==================== 以下为 BLE 接入新增字段（迁移 V2） ====================

    /**
     * 手杖蓝牙地址。
     *
     * <p>Android 侧是 ESP32-S3 的静态 MAC，稳定；iOS 侧由系统按
     * 「每台手机 + 每个 App」生成随机 UUID，换机就变。
     * <b>因此它只作为就近自动重连的提示，设备的权威身份永远是 deviceSn。</b>
     */
    private String bleAddress;

    /** 前方障碍状态 CLEAR/NEAR/DANGER，NULL = 从未收到过 BLE 遥测。 */
    private String obstacleStatus;

    /** 前方障碍距离（cm），来自 BLE 遥测。 */
    private Integer obstacleDistanceCm;

    /**
     * 最近一次障碍遥测时间。
     *
     * <p>与 {@link #lastOnlineAt} 分开存在，是为了区分两种状态：
     * 「手杖在线但手机没连着蓝牙」（lastOnlineAt 在走、本字段停住）
     * 与「手杖整体失联」（两个都停住）。
     */
    private LocalDateTime obstacleReportedAt;

    /** 0 工作（语音播报） / 1 静音。 */
    private Integer muteMode;

    /** 手机侧推算的 BLE 链路 RSSI（dBm），原始值备查；UI 档位仍看 signalLevel。 */
    private Integer bleRssi;

    /**
     * 手机网关与手杖的 BLE 链路：0 未连接 / 1 已连接。
     *
     * <p>这一列解决的是一个真实的一致性风险：障碍状态只在手机连着蓝牙时才有，
     * 一旦断开，云端最后一帧的 DANGER 会永远挂在屏幕上 ——
     * 家属看到「危险」却不知道数据已过期，比什么都不显示更危险。
     */
    private Integer bleConnected;

    /** 蓝牙链路状态最近一次变化时间。 */
    private LocalDateTime bleConnectedAt;

    @TableField(fill = FieldFill.INSERT)
    private LocalDateTime createdAt;

    @TableField(fill = FieldFill.INSERT_UPDATE)
    private LocalDateTime updatedAt;

    /** 障碍状态字符串 → 枚举，无法识别或为空时返回 null。 */
    public ObstacleStatus obstacleStatusEnum() {
        return ObstacleStatus.parse(obstacleStatus);
    }

    /** 手杖是否处于静音模式。NULL 视为未静音。 */
    public boolean isMuted() {
        return muteMode != null && muteMode == MUTE_ON;
    }

    /**
     * BLE 链路是否已连接。
     *
     * <p>刻意不叫 {@code isBleConnected}：字段 {@code bleConnected} 是 Integer，
     * Lombok 会生成 {@code getBleConnected()}，若再手写一个
     * {@code isBleConnected()}，MyBatis-Plus 的 lambda 属性解析与 Jackson
     * 序列化都会看到「同一个属性的两种读法」，容易产生难以定位的歧义 ——
     * 换个名字可彻底避开。
     */
    public boolean isBleLinkUp() {
        return bleConnected != null && bleConnected == BLE_CONNECTED;
    }
}
