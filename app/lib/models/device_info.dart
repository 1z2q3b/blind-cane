/// 设备状态。字段名与后端 `DeviceVO` 保持一致，避免两端各维护一套映射。
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
    );
  }

  static DateTime? _parseTime(Object? raw) {
    if (raw is! String || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

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
class DeviceStatusMessage {
  const DeviceStatusMessage({
    required this.online,
    this.battery,
    this.signalLevel,
  });

  final bool online;
  final int? battery;
  final int? signalLevel;

  factory DeviceStatusMessage.fromJson(Map<String, dynamic> json) {
    return DeviceStatusMessage(
      online: json['online'] as bool? ?? false,
      battery: (json['battery'] as num?)?.toInt(),
      signalLevel: (json['signalLevel'] as num?)?.toInt(),
    );
  }
}
