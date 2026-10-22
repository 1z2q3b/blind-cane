package com.blindcane.guardian.modules.device.entity;

import java.util.Locale;

/**
 * 下行命令白名单（《BLE 对接规格 v1》第 4 节）。
 *
 * <p>规格里手机 → 手杖的通道是单字符 Write，目前只有 {@code M}（切换工作/静音）。
 * 设备端是「收到什么字符就执行什么」，因此服务端必须做白名单 ——
 * 否则一个越权的 App 就能把任意字节写进 RX 特征。
 *
 * <p>用枚举而不是 {@code Set<String>} 的原因：每个命令还要带中文标签
 * （回执日志、STOMP 载荷都要用），枚举天然把「码值 + 语义 + 副作用」绑在一起。
 * 固件后续实现新命令时，在这里加一项即可，控制器与校验逻辑都不用动。
 */
public enum CaneCommand {

    /** M = 切换工作/静音。幂等性由固件的取反实现决定，所以服务端只在回执成功后才提交状态。 */
    M("M", "切换工作/静音模式", true);

    private final String code;
    private final String label;
    /** 该命令是否会改变静音模式 —— 决定回执成功后要不要翻转 mute_mode。 */
    private final boolean toggleMuteMode;

    CaneCommand(String code, String label, boolean toggleMuteMode) {
        this.code = code;
        this.label = label;
        this.toggleMuteMode = toggleMuteMode;
    }

    public String code() {
        return code;
    }

    public String label() {
        return label;
    }

    public boolean togglesMuteMode() {
        return toggleMuteMode;
    }

    /**
     * 解析命令码（大小写不敏感）。
     *
     * @return 不在白名单时返回 {@code null}，由调用方抛 104007
     */
    public static CaneCommand parse(String raw) {
        if (raw == null || raw.isBlank()) {
            return null;
        }
        String normalized = raw.trim().toUpperCase(Locale.ROOT);
        for (CaneCommand command : values()) {
            if (command.code.equals(normalized)) {
                return command;
            }
        }
        return null;
    }

    /** 已支持命令码的展示串（如 {@code M}），用于错误信息与文档。 */
    public static String supportedCodes() {
        StringBuilder sb = new StringBuilder();
        for (CaneCommand command : values()) {
            if (sb.length() > 0) {
                sb.append('/');
            }
            sb.append(command.code);
        }
        return sb.toString();
    }
}
