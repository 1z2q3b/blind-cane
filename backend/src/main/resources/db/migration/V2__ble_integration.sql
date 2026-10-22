-- =============================================================
-- 智能导盲杖 · 家属监护端   迁移 V2：BLE（Nordic UART Service）对接
--
-- 背景：硬件侧协议见《BLE 对接规格 v1》——
--       导盲杖 = BLE 外设(Peripheral/Server)，手机 = 中心(Central/Client)，
--       明文文本协议：上行 `<状态>,<距离cm>`（500ms 一条），下行单字符命令（M = 工作/静音）。
--
-- 本次只新增列，不修改/删除任何已有列与索引，
-- 因此可以在已有数据的库上安全执行，也不会影响 V1 已建好的 9 张表结构。
-- =============================================================

ALTER TABLE device
    -- 手杖蓝牙地址。Android 是硬件 MAC（ESP32-S3 静态地址，稳定）；
    -- iOS 由系统按「每台手机 + 每个 App」生成随机 UUID，换手机就变了。
    -- 结论：这个字段只作为「就近重连的提示」，权威身份永远是 device_sn。
    ADD COLUMN ble_address          VARCHAR(32)  DEFAULT NULL COMMENT '手杖蓝牙地址（Android=MAC / iOS=系统随机 UUID）',
    -- 前方障碍状态，取值严格对应规格里的 CLEAR / NEAR / DANGER。
    -- NULL 表示这台设备从未收到过 BLE 遥测（例如纯 Mock 演示设备）。
    ADD COLUMN obstacle_status      VARCHAR(10)  DEFAULT NULL COMMENT '前方障碍状态 CLEAR/NEAR/DANGER，NULL=无遥测',
    ADD COLUMN obstacle_distance_cm INT          DEFAULT NULL COMMENT '前方障碍距离（cm），来自 BLE 遥测',
    -- 与 last_online_at 分开的理由：
    -- last_online_at 由位置/电量等各类上报刷新，而遥测只在 App 与手杖蓝牙连着时才有。
    -- 两者分开才能区分「手杖在线但手机没连蓝牙」和「手杖整体失联」两种状态。
    ADD COLUMN obstacle_reported_at DATETIME     DEFAULT NULL COMMENT '最近一次障碍遥测时间（BLE 链路活性）',
    -- 手杖当前是工作(播报)还是静音。取值 0/1，与命令 M 的切换结果保持同步。
    ADD COLUMN mute_mode            TINYINT      NOT NULL DEFAULT 0 COMMENT '0 工作（语音播报） / 1 静音',
    -- 手机侧推算的 BLE 链路信号强度（-100 ~ 0 dBm），由 App 的 RSSI 读数换算，
    -- 与 signal_level(1-4) 并存：后者是给 UI 用的档位，前者保留原始值便于排障。
    ADD COLUMN ble_rssi             INT          DEFAULT NULL COMMENT 'BLE 链路 RSSI（dBm），App 侧读取',
    -- 手机网关与手杖的蓝牙链路状态。这一列解决的是一个真实的一致性问题：
    -- 障碍状态是「手机连着蓝牙时」才有的数据，一旦手机与手杖断开，
    -- 云端最后一次收到的 DANGER 会永远停在屏幕上 ——
    -- 家属看到「危险」却不知道数据已经过期，比什么都不显示更危险。
    -- 有了这个标记，App 就能明确显示「蓝牙已断开，以下为最后状态」。
    ADD COLUMN ble_connected        TINYINT      NOT NULL DEFAULT 0 COMMENT '手机网关与手杖的 BLE 链路：0 未连接 / 1 已连接',
    ADD COLUMN ble_connected_at     DATETIME     DEFAULT NULL COMMENT '蓝牙链路状态最近一次变化时间';

-- 按蓝牙地址反查设备（App 扫到手杖后回查是否已绑定过），
-- 不做唯一索引：iOS 的随机 UUID 会让「同一台手杖」在不同手机上得到不同地址，
-- 唯一约束反而会误伤正常绑定。冲突检测放在业务层，属于尽力而为。
ALTER TABLE device ADD KEY idx_ble_address (ble_address);
