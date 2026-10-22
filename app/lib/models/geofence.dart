import 'package:flutter/foundation.dart';

/// 围栏类型。数值与后端 `Geofence.TYPE_SAFE / TYPE_DANGER` 一致，
/// 语义上触发方向是相反的，所以这里把"什么时候提醒"也一并写进枚举，
/// 避免各处 UI 各自拼文案拼出不一致的说法。
enum FenceType {
  safe(1, '安全区', '离开时提醒'),
  danger(2, '危险区', '进入时提醒');

  const FenceType(this.value, this.label, this.ruleLabel);

  final int value;
  final String label;
  final String ruleLabel;

  static FenceType fromValue(int? value) {
    return FenceType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => FenceType.safe,
    );
  }
}

/// 电子围栏（圆形：中心点 + 半径）。
@immutable
class Geofence {
  const Geofence({
    required this.id,
    required this.wardId,
    required this.name,
    required this.centerLng,
    required this.centerLat,
    required this.radiusM,
    required this.fenceType,
    required this.enabled,
    this.createdAt,
  });

  final int id;
  final int wardId;
  final String name;
  final double centerLng;
  final double centerLat;
  final int radiusM;
  final int fenceType;
  final int enabled;
  final DateTime? createdAt;

  bool get isEnabled => enabled == 1;

  FenceType get type => FenceType.fromValue(fenceType);

  factory Geofence.fromJson(Map<String, dynamic> json) {
    return Geofence(
      id: (json['id'] as num).toInt(),
      wardId: (json['wardId'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '未命名围栏',
      centerLng: (json['centerLng'] as num?)?.toDouble() ?? 0,
      centerLat: (json['centerLat'] as num?)?.toDouble() ?? 0,
      radiusM: (json['radiusM'] as num?)?.toInt() ?? 0,
      fenceType: (json['fenceType'] as num?)?.toInt() ?? 1,
      enabled: (json['enabled'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }

  Geofence copyWith({int? enabled}) {
    return Geofence(
      id: id,
      wardId: wardId,
      name: name,
      centerLng: centerLng,
      centerLat: centerLat,
      radiusM: radiusM,
      fenceType: fenceType,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
    );
  }
}

/// 轨迹回放中的一个点。
@immutable
class TrackPoint {
  const TrackPoint({
    required this.lng,
    required this.lat,
    this.at,
    this.speed,
    this.accuracyM,
  });

  final double lng;
  final double lat;
  final DateTime? at;
  final double? speed;
  final double? accuracyM;

  factory TrackPoint.fromJson(Map<String, dynamic> json) {
    return TrackPoint(
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      at: DateTime.tryParse(json['reportedAt'] as String? ?? ''),
      speed: (json['speed'] as num?)?.toDouble(),
      accuracyM: (json['accuracyM'] as num?)?.toDouble(),
    );
  }
}
