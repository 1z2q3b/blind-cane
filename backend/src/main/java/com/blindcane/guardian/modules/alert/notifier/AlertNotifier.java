package com.blindcane.guardian.modules.alert.notifier;

import com.blindcane.guardian.modules.alert.entity.AlertRecord;

/**
 * 告警分发通道抽象。
 *
 * <p>设计成「多实现 + 全部调用」而不是 if-else：S3 会加入
 * WebSocketAlertNotifier（在线家属实时推送）、JpushAlertNotifier（离线兜底），
 * 新增通道只需新加一个 Bean，AlertService 完全不用改。
 *
 * <p>约定：实现方抛出的异常会被 AlertService 吞掉并记日志。
 * 告警已经落库，任何推送通道失败都不能影响告警本身的存在。
 */
public interface AlertNotifier {

    void notify(AlertRecord alert);

    /** 通道名称，仅用于日志排查。 */
    String channelName();
}
