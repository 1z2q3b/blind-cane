-- =============================================================
-- V3：密码登录支持
--
-- 背景：认证方式从「仅短信验证码」扩展为「验证码 / 密码二选一」，
-- 注册流程改为显式注册（手机号 + 密码 + 短信验证码）。
--
-- 设计说明：
--   * password_hash 存 BCrypt 哈希，**绝不存明文**；
--   * 取 NOT NULL DEFAULT '' 而不是可空：MyBatis-Plus 的 updateById
--     会跳过 null 字段（项目在 ble_rssi 上已经踩过一次这个坑，
--     见 DeviceTelemetryServiceImpl 的注释），可空列会让
--     「清空密码」这类操作写不进去；空串即表示「未设置密码」。
-- =============================================================
ALTER TABLE family_user
    ADD COLUMN password_hash VARCHAR(100) NOT NULL DEFAULT '' COMMENT 'BCrypt 密码哈希；空串=未设置密码（仅验证码登录）'
        AFTER phone;
