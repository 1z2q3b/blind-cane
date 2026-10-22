-- =============================================================
-- V4：被监护人档案补充「住址坐标」与「随身电话」
--
-- 为什么需要住址坐标：
--   家庭住址以前只是一个字符串，只能给人看，没法参与任何计算。
--   二期的「手动定位」要让家属在地图上确认家的位置，就必须落经纬度；
--   有了坐标，「离家/到家判断」以及以家为中心的默认围栏才有依据。
--
-- 为什么需要随身电话：
--   一键拨号是告警页最关键的兜底动作（App 内实时语音在现有硬件上做不了，
--   手杖只有 BLE，没有 4G 和音频通道）。号码必须能改，所以落在档案上，
--   而不是写死在配置里。
--
-- 两列都允许为空/空串：存量档案没有这些信息，强行 NOT NULL 会逼出假数据。
-- =============================================================

ALTER TABLE ward
    ADD COLUMN home_lng DOUBLE DEFAULT NULL
        COMMENT '家庭住址经度（手动定位确认；无则 NULL）' AFTER home_address,
    ADD COLUMN home_lat DOUBLE DEFAULT NULL
        COMMENT '家庭住址纬度（手动定位确认；无则 NULL）' AFTER home_lng,
    ADD COLUMN contact_phone VARCHAR(20) NOT NULL DEFAULT ''
        COMMENT '被监护人随身电话，用于一键拨号；空串表示未填写' AFTER home_lat;
