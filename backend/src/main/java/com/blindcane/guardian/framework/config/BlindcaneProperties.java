package com.blindcane.guardian.framework.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

/**
 * 业务配置集中入口（对应 application.yml 的 blindcane.* 段）。
 *
 * <p>把所有「可插拔能力」的开关收在一个类里，是为了让 Mock 降级策略一目了然：
 * 任何一项缺密钥（sms/jpush/amap）都只影响自身，不影响主链路。
 */
@Data
@Component
@ConfigurationProperties(prefix = "blindcane")
public class BlindcaneProperties {

    private Jwt jwt = new Jwt();
    private Sms sms = new Sms();
    private Jpush jpush = new Jpush();
    private Amap amap = new Amap();
    private Crypto crypto = new Crypto();
    private Simulator simulator = new Simulator();
    private Device device = new Device();
    private Location location = new Location();
    private Security security = new Security();

    @Data
    public static class Jwt {
        /** 签名密钥原文，实际按 SHA-256 派生成 32 字节 HMAC key，因此长度不受限。 */
        private String secret;
        private String issuer = "blind-cane-guardian";
        private long accessTokenTtlMinutes = 120;
        private long refreshTokenTtlDays = 7;
    }

    @Data
    public static class Sms {
        /** false = Mock：验证码由后端随机生成、打印日志，响应体回显 mockCode。 */
        private boolean enabled = false;
        private int intervalSeconds = 60;
        private int codeTtlSeconds = 300;
        private int maxPerDay = 10;
    }

    @Data
    public static class Jpush {
        private boolean enabled = false;
        private String appKey;
        private String masterSecret;
    }

    @Data
    public static class Amap {
        /** 高德 Web 服务 Key，为空时逆地理编码降级为返回原始坐标。 */
        private String webKey;
    }

    @Data
    public static class Crypto {
        /** AES 密钥原文，按 SHA-256 派生成 32 字节，用于病史备注加密。 */
        private String aesSecret;
    }

    @Data
    public static class Simulator {
        private boolean enabled = true;
        private String demoDeviceSn = "BC-2024-DEMO01";
        private String demoDeviceName = "演示导盲杖";
        private String demoFirmware = "v0.9.2-demo";
        private double originLng = 113.7845;
        private double originLat = 34.8133;
        private int reportIntervalMs = 10_000;
        /** 是否自动随机游走。演示时想冻结轨迹（便于讲解某个界面）或在自动化验证里要确定性结果时置 false。 */
        private boolean positionDriftEnabled = true;
        private double stepMeters = 1.0;
        private int initialBattery = 85;
        private String batteryDecayCron = "0 0 * * * *";
        private int fallConfirmTimeoutSeconds = 30;
        /**
         * 演示设备的「虚拟蓝牙地址」。真实硬件地址由 ESP32 决定，
         * 这里给固定值是为了在没有蓝牙硬件时也能跑通
         * 「绑定 → 连接 → 遥测 → 命令」全链路（见 MockBleController）。
         */
        private String demoBleAddress;
    }

    @Data
    public static class Device {
        private int offlineThresholdMinutes = 5;
        private long offlineScanIntervalMs = 60000;
        private int lowBatteryThreshold = 20;
        private int lowBatteryStep = 10;

        // ------- 以下为 BLE 接入参数（《BLE 对接规格 v1》）-------

        /**
         * 遥测节流窗口（ms）。手杖 500ms 一帧，靠这个窗口把稳态落库压到 ≤1 次/秒；
         * 状态变化不受窗口限制，危险状态仍然零延迟可见。
         */
        private int telemetryMinIntervalMs = 1000;

        /** 障碍状态阈值：≥nearCm 畅通 / dangerCm~nearCm 有障碍 / &lt;dangerCm 危险。 */
        private int obstacleNearCm = 100;
        private int obstacleDangerCm = 20;
    }

    @Data
    public static class Location {
        private int flushBatchSize = 200;
        private long flushIntervalMs = 5000;
        private int redisTtlMinutes = 30;
    }

    @Data
    public static class Security {
        private List<String> permitAllPaths = new ArrayList<>();
    }
}
