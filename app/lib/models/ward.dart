import 'device_info.dart';

/// 被监护人（列表形态，不含病史）。
class Ward {
  const Ward({
    required this.id,
    required this.name,
    this.relation,
    this.birthYear,
    this.homeAddress,
    this.homeLng,
    this.homeLat,
    this.contactPhone,
    this.myRole,
    this.device,
    this.latestLocation,
    this.pendingAlertCount = 0,
  });

  final int id;
  final String name;
  final String? relation;
  final int? birthYear;
  final String? homeAddress;

  /// 住址坐标（家属「手动定位」确认后写入）。两个都为 null 表示还没定位过。
  final double? homeLng;
  final double? homeLat;

  /// 随身电话，一键拨号用。空串/ null 表示未填写。
  final String? contactPhone;

  /// 1 = 主监护人，2 = 协作家属。
  final int? myRole;
  final DeviceInfo? device;
  final LatestLocation? latestLocation;
  final int pendingAlertCount;

  bool get isPrimaryGuardian => myRole == 1;

  /// 是否已有可拨打的号码（去空格后非空）。
  bool get hasContactPhone =>
      contactPhone != null && contactPhone!.trim().isNotEmpty;

  /// 是否已完成手动定位。
  bool get hasHomeLocation => homeLng != null && homeLat != null;

  factory Ward.fromJson(Map<String, dynamic> json) {
    return Ward(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '未命名',
      relation: json['relation'] as String?,
      birthYear: (json['birthYear'] as num?)?.toInt(),
      homeAddress: json['homeAddress'] as String?,
      homeLng: (json['homeLng'] as num?)?.toDouble(),
      homeLat: (json['homeLat'] as num?)?.toDouble(),
      contactPhone: json['contactPhone'] as String?,
      myRole: (json['myRole'] as num?)?.toInt(),
      device: json['device'] == null
          ? null
          : DeviceInfo.fromJson(json['device'] as Map<String, dynamic>),
      latestLocation: json['latestLocation'] == null
          ? null
          : LatestLocation.fromJson(
              json['latestLocation'] as Map<String, dynamic>),
      pendingAlertCount: (json['pendingAlertCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// 年龄由出生年份推算，避免后端与前端各存一份会过期的年龄。
  int? get age {
    final year = birthYear;
    if (year == null || year <= 1900) {
      return null;
    }
    final value = DateTime.now().year - year;
    return value >= 0 && value < 130 ? value : null;
  }
}

/// 被监护人详情（含解密后的病史备注）。
class WardDetail extends Ward {
  const WardDetail({
    required super.id,
    required super.name,
    super.relation,
    super.birthYear,
    super.homeAddress,
    super.homeLng,
    super.homeLat,
    super.contactPhone,
    super.myRole,
    super.device,
    super.latestLocation,
    super.pendingAlertCount,
    this.medicalNotes,
    this.primaryUserId,
    this.createdAt,
  });

  /// 病史备注，仅详情接口返回（列表接口不返回，减少敏感信息暴露面）。
  final String? medicalNotes;
  final int? primaryUserId;
  final DateTime? createdAt;

  factory WardDetail.fromJson(Map<String, dynamic> json) {
    final base = Ward.fromJson(json);
    return WardDetail(
      id: base.id,
      name: base.name,
      relation: base.relation,
      birthYear: base.birthYear,
      homeAddress: base.homeAddress,
      homeLng: base.homeLng,
      homeLat: base.homeLat,
      contactPhone: base.contactPhone,
      myRole: base.myRole,
      device: base.device,
      latestLocation: base.latestLocation,
      pendingAlertCount: base.pendingAlertCount,
      medicalNotes: json['medicalNotes'] as String?,
      primaryUserId: (json['primaryUserId'] as num?)?.toInt(),
      createdAt: json['createdAt'] is String
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }
}

/// 最新位置（Redis 热数据 / WebSocket 推送共用）。
class LatestLocation {
  const LatestLocation({
    required this.lng,
    required this.lat,
    this.accuracyM,
    this.speed,
    this.reportedAt,
    this.address,
  });

  final double lng;
  final double lat;
  final double? accuracyM;
  final double? speed;

  /// 设备上报时间（epoch 毫秒）。
  final int? reportedAt;

  /// 逆地理文案。未配置高德 Key 时为空，UI 需降级显示坐标。
  final String? address;

  factory LatestLocation.fromJson(Map<String, dynamic> json) {
    return LatestLocation(
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      accuracyM: (json['accuracyM'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      reportedAt: (json['reportedAt'] as num?)?.toInt(),
      address: json['address'] as String?,
    );
  }

  DateTime? get reportedAtTime =>
      reportedAt == null ? null : DateTime.fromMillisecondsSinceEpoch(reportedAt!);

  /// 坐标文案：没有逆地理结果时退化成「纬度, 经度」，保证家属至少能定位。
  String get displayAddress {
    if (address != null && address!.isNotEmpty) {
      return address!;
    }
    return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  /// 「3 分钟前」这类相对时间。
  String get freshnessText {
    final time = reportedAtTime;
    if (time == null) {
      return '未知时间';
    }
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 20) {
      return '刚刚';
    }
    if (diff.inMinutes < 1) {
      return '${diff.inSeconds} 秒前';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} 分钟前';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} 小时前';
    }
    return '${diff.inDays} 天前';
  }

  /// 位置是否已经算「陈旧」：超过 2 分钟没有新数据就不该继续显示为实时。
  bool get isStale {
    final time = reportedAtTime;
    if (time == null) {
      return true;
    }
    return DateTime.now().difference(time).inSeconds > 120;
  }
}
