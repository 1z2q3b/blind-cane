import '../core/ble/ble_protocol.dart';

/// 设备状态。字段名与后端 `DeviceVO` 保持一致，避免两端各维护一套映射。
///
/// BLE 接入后新增了「蓝牙链路」与「障碍状态」两组字段。渲染时必须守这个次序：
/// `bleConnected == false` 时，`obstacleStatus` 只是**断开前的最后读数**，
/// 不能当作当前状态下结论 —— 否则一个过期的「危险 12cm」会一直吓着家属。
class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.deviceSn,
    required this.name,
    this.wardId,
    this.battery,
    this.signalLevel,
    required this.online,
    this.lastOnlineAt,
    this.offlineSeconds,
    this.firmwareVersion,
    this.bleAddress,
    this.bleConnected = false,
    this.bleConnectedAt,
    this.bleRssi,
    this.obstacleStatus,
    this.obstacleDistanceCm,
    this.obstacleReportedAt,
    this.obstacleSeconds,
    this.muteMode,
  });

  final int id;
  final String deviceSn;
  final String name;
  final int? wardId;
  final int? battery;
  final int? signalLevel;
  final bool online;
  final DateTime? lastOnlineAt;

  /// 距最后一次上报的秒数，后端已算好，前端不用再对时区做换算。
  final int? offlineSeconds;
  final String? firmwareVersion;

  // ---------------- BLE 接入新增 ----------------

  /// 手杖蓝牙地址（Android=MAC / iOS=随机 UUID）。空表示尚未登记，
  /// 此时只能靠扫描找到手杖，无法自动重连。
  final String? bleAddress;

  /// 手机网关与手杖的 BLE 链路是否已建立。
  final bool bleConnected;
  final DateTime? bleConnectedAt;

  /// 链路原始 RSSI（dBm）。UI 档位仍看 [signalLevel]，这是排障用的原始值。
  final int? bleRssi;

  /// 障碍状态原始串（CLEAR/NEAR/DANGER），可能为 null（从未收到遥测）。
  final String? obstacleStatus;
  final int? obstacleDistanceCm;
  final DateTime? obstacleReportedAt;

  /// 距最近一次障碍遥测过去多少秒 —— 数据新鲜度。
  final int? obstacleSeconds;

  /// 0 工作（语音播报） / 1 静音。
  final int? muteMode;

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      id: (json['id'] as num?)?.toInt() ?? 0,
      deviceSn: json['deviceSn'] as String? ?? '',
      name: json['name'] as String? ?? '导盲杖',
      wardId: (json['wardId'] as num?)?.toInt(),
      battery: (json['battery'] as num?)?.toInt(),
      signalLevel: (json['signalLevel'] as num?)?.toInt(),
      online: json['online'] as bool? ?? false,
      lastOnlineAt: _parseTime(json['lastOnlineAt']),
      offlineSeconds: (json['offlineSeconds'] as num?)?.toInt(),
      firmwareVersion: json['firmwareVersion'] as String?,
      bleAddress: json['bleAddress'] as String?,
      bleConnected: json['bleConnected'] as bool? ?? false,
      bleConnectedAt: _parseTime(json['bleConnectedAt']),
      bleRssi: (json['bleRssi'] as num?)?.toInt(),
      obstacleStatus: json['obstacleStatus'] as String?,
      obstacleDistanceCm: (json['obstacleDistanceCm'] as num?)?.toInt(),
      obstacleReportedAt: _parseTime(json['obstacleReportedAt']),
      obstacleSeconds: (json['obstacleSeconds'] as num?)?.toInt(),
      muteMode: (json['muteMode'] as num?)?.toInt(),
    );
  }

  static DateTime? _parseTime(Object? raw) {
    if (raw is! String || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  /// 后端状态串 → 枚举。识别不了就返回 null，由界面显示「未知」而不是猜一个。
  ObstacleStatus? get obstacle =>
      obstacleStatus == null ? null : ObstacleStatus.tryParse(obstacleStatus!);

  /// 障碍数据是否可当作实时值使用。
  bool get hasLiveObstacle => bleConnected && obstacleStatus != null;

  bool get muted => muteMode == 1;

  /// 电量分级，用于首页徽章配色。低电量必须是能一眼看到的强提示色。
  BatteryLevel get batteryLevel {
    final value = battery ?? 100;
    if (value <= 10) {
      return BatteryLevel.critical;
    }
    if (value <= 20) {
      return BatteryLevel.low;
    }
    return BatteryLevel.normal;
  }

  /// 人类可读的「最后在线」文案。
  String get lastOnlineText {
    if (online) {
      return '在线';
    }
    final seconds = offlineSeconds;
    if (seconds == null) {
      return '已离线';
    }
    if (seconds < 60) {
      return '刚刚离线';
    }
    if (seconds < 3600) {
      return '${seconds ~/ 60} 分钟前';
    }
    if (seconds < 86400) {
      return '${seconds ~/ 3600} 小时前';
    }
    return '${seconds ~/ 86400} 天前';
  }
}

enum BatteryLevel { normal, low, critical }

/// WebSocket `/topic/ward/{id}/device` 推送的设备状态。
///
/// 契约同 [DeviceInfo]：`bleConnected=false` 时 `obstacleStatus` 是最后读数而非当前状态。
class DeviceStatusMessage {
  const DeviceStatusMessage({
    required this.online,
    this.battery,
    this.signalLevel,
    this.bleConnected = false,
    this.obstacleStatus,
    this.obstacleDistanceCm,
    this.muteMode,
    this.obstacleReportedAt,
  });

  final bool online;
  final int? battery;
  final int? signalLevel;
  final bool bleConnected;
  final String? obstacleStatus;
  final int? obstacleDistanceCm;
  final int? muteMode;
  final DateTime? obstacleReportedAt;

  ObstacleStatus? get obstacle =>
      obstacleStatus == null ? null : ObstacleStatus.tryParse(obstacleStatus!);

  bool get hasLiveObstacle => bleConnected && obstacleStatus != null;

  factory DeviceStatusMessage.fromJson(Map<String, dynamic> json) {
    return DeviceStatusMessage(
      online: json['online'] as bool? ?? false,
      battery: (json['battery'] as num?)?.toInt(),
      signalLevel: (json['signalLevel'] as num?)?.toInt(),
      bleConnected: json['bleConnected'] as bool? ?? false,
      obstacleStatus: json['obstacleStatus'] as String?,
      obstacleDistanceCm: (json['obstacleDistanceCm'] as num?)?.toInt(),
      muteMode: (json['muteMode'] as num?)?.toInt(),
      obstacleReportedAt: DeviceInfo._parseTime(json['obstacleReportedAt']),
    );
  }
}

/// WebSocket `/topic/ward/{id}/command` 推送的手杖命令。
///
/// 后端**不直接连蓝牙**：它把命令广播到 ward 主题，
/// 由真正与手杖连着的那台手机写入 RX 特征。没有手机连着时命令无人执行，
/// 界面上必须明确提示这一点，否则按钮点下去毫无反应会被当成软件坏了。
class DeviceCommandMessage {
  const DeviceCommandMessage({
    required this.command,
    required this.deviceId,
    required this.issuedAt,
    this.commandName,
    this.wardId,
    this.muteMode,
  });

  /// 命令码，如 `M`。
  final String command;

  /// 命令中文名，由后端下发，App 不再维护一份码值 → 文案的映射。
  final String? commandName;
  final int? wardId;
  final int deviceId;

  /// 执行成功后**预期**的静音模式，仅用于等待回执期间的乐观显示。
  final int? muteMode;

  /// 下发时刻（毫秒时间戳），用于丢弃过期重放。
  final int issuedAt;

  factory DeviceCommandMessage.fromJson(Map<String, dynamic> json) {
    return DeviceCommandMessage(
      command: json['command'] as String? ?? '',
      commandName: json['commandName'] as String?,
      wardId: (json['wardId'] as num?)?.toInt(),
      deviceId: (json['deviceId'] as num?)?.toInt() ?? 0,
      muteMode: (json['muteMode'] as num?)?.toInt(),
      issuedAt: (json['issuedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 遥测上报回执。`accepted=false` 说明这一帧被后端节流丢弃（状态未变且速率超窗口）。
class TelemetryAck {
  const TelemetryAck({
    required this.accepted,
    this.reason,
    this.obstacleStatus,
    this.distanceCm,
    this.muteMode,
  });

  final bool accepted;
  final String? reason;
  final String? obstacleStatus;
  final int? distanceCm;
  final int? muteMode;

  factory TelemetryAck.fromJson(Map<String, dynamic> json) {
    return TelemetryAck(
      accepted: json['accepted'] as bool? ?? false,
      reason: json['reason'] as String?,
      obstacleStatus: json['obstacleStatus'] as String?,
      distanceCm: (json['distanceCm'] as num?)?.toInt(),
      muteMode: (json['muteMode'] as num?)?.toInt(),
    );
  }
}
