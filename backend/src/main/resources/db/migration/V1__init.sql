-- =============================================================
-- 智能导盲杖 · 家属监护端   初始化脚本 V1
-- 说明：一次性建好阶段一 + 阶段二所需的全部 9 张表，
--       避免二期再做破坏性结构变更（二期只加数据、不改结构）。
-- 约定：命名小写下划线；每表含 created_at / updated_at，
--       由 MyBatis-Plus MetaObjectAutoFillHandler 自动填充。
-- =============================================================

-- -------------------------------------------------------------
-- 6.1 family_user 家属用户
-- -------------------------------------------------------------
CREATE TABLE family_user (
    id                    BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    phone                 VARCHAR(20)  NOT NULL                COMMENT '手机号（登录账号）',
    nickname              VARCHAR(50)           DEFAULT NULL   COMMENT '昵称',
    avatar                VARCHAR(255)          DEFAULT NULL   COMMENT '头像 URL',
    status                TINYINT      NOT NULL DEFAULT 0      COMMENT '0正常 / 1禁用',
    -- 通知偏好（各类告警的推送/应用内开关），JSON 字符串；
    -- 单独建表对 MVP 属于过度设计，用 JSON 列更省事，二期若需查询再拆表
    notification_settings VARCHAR(500)          DEFAULT NULL   COMMENT '通知偏好 JSON',
    created_at            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_phone (phone)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '家属用户';

-- -------------------------------------------------------------
-- 6.2 ward 被监护人档案
-- -------------------------------------------------------------
CREATE TABLE ward (
    id              BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    name            VARCHAR(50)  NOT NULL                COMMENT '姓名',
    relation        VARCHAR(20)           DEFAULT NULL   COMMENT '与操作家属的关系（父亲/母亲/配偶/其他）',
    birth_year      INT                   DEFAULT NULL   COMMENT '出生年份',
    home_address    VARCHAR(255)          DEFAULT NULL   COMMENT '住址',
    -- 病史备注：AES-GCM 应用层加密后以 Base64 存储。
    -- 密文比明文长约 1/3 再加随机 IV 与认证标签，故 500 位明文需约 700+ 字符容量，
    -- 这里放宽到 1000，避免加密后截断（对提示词 6.2 的 VARCHAR(500) 的工程化调整）
    medical_notes   VARCHAR(1000)         DEFAULT NULL   COMMENT '病史备注（AES-GCM 加密存储）',
    primary_user_id BIGINT       NOT NULL                COMMENT '主监护人 family_user.id',
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_primary_user (primary_user_id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '被监护人档案';

-- -------------------------------------------------------------
-- 6.3 ward_guardian 监护关系（多对多：1 名被监护人 ← N 名家属）
-- -------------------------------------------------------------
CREATE TABLE ward_guardian (
    id            BIGINT      NOT NULL AUTO_INCREMENT COMMENT '主键',
    ward_id       BIGINT      NOT NULL                COMMENT '被监护人 ward.id',
    user_id       BIGINT      NOT NULL                COMMENT '监护人 family_user.id',
    role          TINYINT     NOT NULL DEFAULT 2      COMMENT '1主监护人 / 2副监护人',
    invite_status TINYINT     NOT NULL DEFAULT 1      COMMENT '0待接受 / 1已接受 / 2已解除',
    created_at    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_ward_user (ward_id, user_id),
    KEY idx_user (user_id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '监护关系';

-- -------------------------------------------------------------
-- 6.4 device 导盲杖设备
-- -------------------------------------------------------------
CREATE TABLE device (
    id               BIGINT      NOT NULL AUTO_INCREMENT COMMENT '主键',
    device_sn        VARCHAR(50) NOT NULL                COMMENT '设备序列号',
    name             VARCHAR(50)          DEFAULT NULL   COMMENT '设备名称（默认 XX的导盲杖）',
    ward_id          BIGINT               DEFAULT NULL   COMMENT '当前绑定被监护人，NULL=未绑定',
    battery          TINYINT     NOT NULL DEFAULT 100    COMMENT '电量 0-100',
    signal_level     TINYINT     NOT NULL DEFAULT 4      COMMENT '信号强度 1-4',
    online           TINYINT     NOT NULL DEFAULT 0      COMMENT '0离线 / 1在线',
    last_online_at   DATETIME             DEFAULT NULL   COMMENT '最后上报时间',
    firmware_version VARCHAR(20)          DEFAULT NULL   COMMENT '固件版本',
    -- 离线告警去抖标记：同一离线周期只发一次告警，
    -- 设备恢复上报后由上报逻辑重置为 0（对应提示词 4.4 的去抖要求）
    offline_notified TINYINT     NOT NULL DEFAULT 0      COMMENT '离线告警是否已发出：0否 / 1是',
    created_at       DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_device_sn (device_sn),
    KEY idx_ward (ward_id),
    -- 离线检测任务每 60s 扫一次，走这个联合索引避免全表扫
    KEY idx_online_scan (online, last_online_at)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '导盲杖设备';

-- -------------------------------------------------------------
-- 6.5 location_record 位置记录（历史轨迹，二期回放用）
-- -------------------------------------------------------------
CREATE TABLE location_record (
    id          BIGINT   NOT NULL AUTO_INCREMENT COMMENT '主键',
    ward_id     BIGINT   NOT NULL                COMMENT '被监护人 ward.id',
    device_id   BIGINT   NOT NULL                COMMENT '设备 device.id',
    -- MySQL 要求：只有 NOT NULL 的空间列才能建 SPATIAL INDEX；
    -- 且 SRID 必须显式声明，否则 ST_Distance_Sphere 等函数行为不确定
    location    POINT    NOT NULL SRID 4326      COMMENT '经纬度坐标',
    accuracy_m  FLOAT             DEFAULT NULL   COMMENT '定位精度（米）',
    speed       FLOAT             DEFAULT NULL   COMMENT '速度（m/s）',
    reported_at DATETIME NOT NULL                COMMENT '上报时间',
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_ward_reported (ward_id, reported_at),
    SPATIAL INDEX idx_location (location)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '位置记录';

-- -------------------------------------------------------------
-- 6.6 alert_record 告警记录
-- -------------------------------------------------------------
CREATE TABLE alert_record (
    id              BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    ward_id         BIGINT       NOT NULL                COMMENT '被监护人 ward.id',
    device_id       BIGINT                DEFAULT NULL   COMMENT '设备 device.id',
    alert_type      VARCHAR(20)  NOT NULL                COMMENT 'SOS / FALL_DETECTED / LOW_BATTERY / DEVICE_OFFLINE / GEOFENCE_EXIT / GEOFENCE_ENTER',
    severity        TINYINT      NOT NULL DEFAULT 2      COMMENT '1高（SOS/跌倒）/ 2中 / 3低',
    lng             DOUBLE                DEFAULT NULL   COMMENT '告警经度',
    lat             DOUBLE                DEFAULT NULL   COMMENT '告警纬度',
    address         VARCHAR(255)          DEFAULT NULL   COMMENT '逆地理文案',
    status          TINYINT      NOT NULL DEFAULT 0      COMMENT '0待处理 / 1已处理 / 2误报',
    handler_user_id BIGINT                DEFAULT NULL   COMMENT '处理人 family_user.id',
    handled_at      DATETIME              DEFAULT NULL   COMMENT '处理时间',
    note            VARCHAR(255)          DEFAULT NULL   COMMENT '处理备注',
    -- 「跌倒 30 秒未确认自动升级」的状态位。
    -- 刻意落库而不是放内存定时器：后端重启后仍未确认的疑似跌倒能被扫描任务补升级，不丢事件
    pending_confirm TINYINT      NOT NULL DEFAULT 0      COMMENT '1=疑似待确认（跌倒升级用）/ 0=已定稿',
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_ward_status (ward_id, status),
    KEY idx_ward_created (ward_id, created_at),
    KEY idx_type_status (alert_type, status),
    KEY idx_pending_confirm (pending_confirm, created_at)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '告警记录';

-- -------------------------------------------------------------
-- 6.7 geofence 电子围栏（二期功能，表先建好）
-- -------------------------------------------------------------
CREATE TABLE geofence (
    id          BIGINT      NOT NULL AUTO_INCREMENT COMMENT '主键',
    ward_id     BIGINT      NOT NULL                COMMENT '归属被监护人',
    name        VARCHAR(50) NOT NULL                COMMENT '围栏名称',
    center_lng  DOUBLE      NOT NULL                COMMENT '中心点经度',
    center_lat  DOUBLE      NOT NULL                COMMENT '中心点纬度',
    radius_m    INT         NOT NULL                COMMENT '半径（米）',
    fence_type  TINYINT     NOT NULL DEFAULT 1      COMMENT '1安全区（离开提醒）/ 2危险区（进入提醒）',
    enabled     TINYINT     NOT NULL DEFAULT 1      COMMENT '启用开关：0关 / 1开',
    created_at  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_ward (ward_id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '电子围栏';

-- -------------------------------------------------------------
-- 6.8 emergency_contact 紧急联系人
-- -------------------------------------------------------------
CREATE TABLE emergency_contact (
    id              BIGINT      NOT NULL AUTO_INCREMENT COMMENT '主键',
    ward_id         BIGINT      NOT NULL                COMMENT '归属被监护人',
    name            VARCHAR(50) NOT NULL                COMMENT '姓名',
    phone           VARCHAR(20) NOT NULL                COMMENT '电话（盲人随身电话优先）',
    relation        VARCHAR(20)          DEFAULT NULL   COMMENT '关系',
    notify_channels VARCHAR(30) NOT NULL DEFAULT 'CALL' COMMENT '通知渠道组合：PUSH,SMS,CALL',
    priority        INT         NOT NULL DEFAULT 1      COMMENT '通知优先级，越小越先通知',
    created_at      DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_ward (ward_id, priority)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '紧急联系人';

-- -------------------------------------------------------------
-- 6.9 push_token 推送令牌
-- -------------------------------------------------------------
CREATE TABLE push_token (
    id              BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    user_id         BIGINT       NOT NULL                COMMENT '家属 family_user.id',
    channel         VARCHAR(20)  NOT NULL DEFAULT 'JPUSH' COMMENT '推送渠道',
    registration_id VARCHAR(100) NOT NULL                COMMENT '极光 registration_id',
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    -- 同一设备的 registration_id 只保留一条，重装/换号时按此做 upsert
    UNIQUE KEY uk_channel_reg (channel, registration_id),
    KEY idx_user (user_id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '推送令牌';
