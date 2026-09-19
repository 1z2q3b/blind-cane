/// 告警类型。与后端 `AlertType` 枚举名一一对应。
enum AlertKind {
  sos('SOS', '一键求助', 1),
  fall('FALL_DETECTED', '跌倒', 1),
  offline('DEVICE_OFFLINE', '设备离线', 2),
  lowBattery('LOW_BATTERY', '低电量', 3),
  geofenceExit('GEOFENCE_EXIT', '离开安全区', 2),
  geofenceEnter('GEOFENCE_ENTER', '进入区域', 3),
  unknown('UNKNOWN', '其他', 3);

  const AlertKind(this.code, this.label, this.defaultSeverity);

  final String code;
  final String label;
  final int defaultSeverity;

  static AlertKind fromCode(String? code) {
    return AlertKind.values.firstWhere(
      (e) => e.code == code,
      orElse: () => AlertKind.unknown,
    );
  }
}

/// 告警记录。字段与后端 `AlertVO` 完全一致（REST 与 WebSocket 共用同一形态）。
class AlertRecord {
  const AlertRecord({
    required this.id,
    required this.wardId,
    this.wardName,
    this.deviceId,
    required this.alertType,
    required this.severity,
    this.severityText,
    this.lng,
    this.lat,
    this.address,
    required this.status,
    this.statusText,
    this.handlerUserId,
    this.handledAt,
    this.note,
    this.pendingConfirm,
    this.createdAt,
  });

  /// status：0 待处理 / 1 已处理 / 2 误报。
  static const int statusPending = 0;
  static const int statusResolved = 1;
  static const int statusFalseAlarm = 2;

  /// severity：1 紧急 / 2 警示 / 3 提示。
  static const int severityCritical = 1;
  static const int severityWarning = 2;

  final int id;
  final int wardId;
  final String? wardName;
  final int? deviceId;
  final String alertType;
  final int severity;
  final String? severityText;
  final double? lng;
  final double? lat;
  final String? address;
  final int status;
  final String? statusText;
  final int? handlerUserId;
  final DateTime? handledAt;
  final String? note;

  /// 1 = 疑似待确认（跌倒 30 秒升级窗口内）。
  final int? pendingConfirm;
  final DateTime? createdAt;

  AlertKind get kind => AlertKind.fromCode(alertType);

  bool get isPending => status == statusPending;
  bool get isCritical => severity == severityCritical;

  /// 是否处于「疑似跌倒待确认」状态——UI 据此显示倒计时确认条。
  bool get isAwaitingConfirm => pendingConfirm == 1 && isPending;

  bool get hasLocation => lng != null && lat != null;

  String get statusLabel =>
      statusText?.isNotEmpty == true ? statusText! : switch (status) {
        statusResolved => '已处理',
        statusFalseAlarm => '误报',
        _ => '待处理',
      };

  String get severityLabel =>
      severityText?.isNotEmpty == true ? severityText! : switch (severity) {
        severityCritical => '紧急',
        severityWarning => '警示',
        _ => '提示',
      };

  /// 是否需要全屏强提醒：只有紧急且未处理才弹。
  /// 低电量、离线这类告警打断家属做任何事都是骚扰。
  bool get requiresFullScreen => isCritical && isPending;

  factory AlertRecord.fromJson(Map<String, dynamic> json) {
    return AlertRecord(
      id: (json['id'] as num?)?.toInt() ?? 0,
      wardId: (json['wardId'] as num?)?.toInt() ?? 0,
      wardName: json['wardName'] as String?,
      deviceId: (json['deviceId'] as num?)?.toInt(),
      alertType: json['alertType'] as String? ?? 'UNKNOWN',
      severity: (json['severity'] as num?)?.toInt() ?? 3,
      severityText: json['severityText'] as String?,
      lng: (json['lng'] as num?)?.toDouble(),
      lat: (json['lat'] as num?)?.toDouble(),
      address: json['address'] as String?,
      status: (json['status'] as num?)?.toInt() ?? 0,
      statusText: json['statusText'] as String?,
      handlerUserId: (json['handlerUserId'] as num?)?.toInt(),
      handledAt: json['handledAt'] is String
          ? DateTime.tryParse(json['handledAt'] as String)
          : null,
      note: json['note'] as String?,
      pendingConfirm: (json['pendingConfirm'] as num?)?.toInt(),
      createdAt: json['createdAt'] is String
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }

  AlertRecord copyWith({int? status, int? pendingConfirm, String? note, DateTime? handledAt}) {
    return AlertRecord(
      id: id,
      wardId: wardId,
      wardName: wardName,
      deviceId: deviceId,
      alertType: alertType,
      severity: severity,
      severityText: severityText,
      lng: lng,
      lat: lat,
      address: address,
      status: status ?? this.status,
      statusText: statusText,
      handlerUserId: handlerUserId,
      handledAt: handledAt ?? this.handledAt,
      note: note ?? this.note,
      pendingConfirm: pendingConfirm ?? this.pendingConfirm,
      createdAt: createdAt,
    );
  }
}

/// 待处理告警角标。
class PendingCount {
  const PendingCount({required this.total, required this.byWard});

  final int total;

  /// `{ wardId: count }`，后端返回的 JSON key 是字符串。
  final Map<int, int> byWard;

  factory PendingCount.fromJson(Map<String, dynamic> json) {
    final raw = (json['byWard'] as Map<String, dynamic>?) ?? const {};
    final byWard = <int, int>{};
    raw.forEach((key, value) {
      final wardId = int.tryParse(key);
      if (wardId != null && value is num) {
        byWard[wardId] = value.toInt();
      }
    });
    return PendingCount(
      total: (json['total'] as num?)?.toInt() ?? 0,
      byWard: byWard,
    );
  }

  int countOf(int wardId) => byWard[wardId] ?? 0;

  static const empty = PendingCount(total: 0, byWard: {});
}
