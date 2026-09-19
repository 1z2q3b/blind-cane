import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_response.dart';
import '../models/ward.dart';
import 'providers.dart';

/// 一个轨迹点。
@immutable
class TrailPoint {
  const TrailPoint({required this.lng, required this.lat, required this.at});

  final double lng;
  final double lat;
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is TrailPoint && other.lng == lng && other.lat == lat && other.at == at;

  @override
  int get hashCode => Object.hash(lng, lat, at);
}

@immutable
class LocationState {
  const LocationState({
    this.latest,
    this.trail = const [],
    this.loading = false,
    this.error,
  });

  final LatestLocation? latest;

  /// 客户端本地累积的轨迹点（不落库，仅用于「最近走了哪些路」的直观展示）。
  ///
  /// 为什么不在后端加轨迹接口：提示词把「轨迹回放」划到了二期，
  /// 一期用本地累积已经能满足「看得见老人在动」的演示效果，
  /// 不引入新的存储与查询成本。
  final List<TrailPoint> trail;

  final bool loading;
  final String? error;

  bool get hasData => latest != null;

  bool get isEmpty => latest == null && !loading;

  /// 在已有轨迹的基础上追加一个点。
  LocationState appendPoint(LatestLocation location) {
    final next = <TrailPoint>[
      ...trail,
      TrailPoint(
        lng: location.lng,
        lat: location.lat,
        at: location.reportedAtTime ?? DateTime.now(),
      ),
    ];
    return LocationState(
      latest: location,
      // 上限 200 点：按 10 秒一次上报算约 33 分钟，够画出一条像样的路径，
      // 又不会让自绘折线的每帧计算量失控。
      trail: next.length > 200 ? next.sublist(next.length - 200) : next,
      loading: false,
    );
  }

  LocationState copyWith({
    LatestLocation? latest,
    List<TrailPoint>? trail,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return LocationState(
      latest: latest ?? this.latest,
      trail: trail ?? this.trail,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 当前被监护人的实时位置 + 本地轨迹。
class LocationNotifier extends Notifier<LocationState> {
  @override
  LocationState build() => const LocationState();

  /// 先用 REST 拉一次，避免刚进页面时空白等推送。
  Future<void> load(int wardId) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final location = await ref.read(repositoryProvider).latestLocation(wardId);
      if (location == null) {
        // 后端返回 null 表示「该被监护人还没有任何位置数据」，
        // 这不是错误，界面上应显示「等待设备上报」而不是报错
        state = const LocationState();
        return;
      }
      // 只有和上一个轨迹点有明显位移才追加：
      // 设备静止时也会每 10 秒上报一次，全部画上去会让折线变成一个黑点
      final last = state.trail.isEmpty ? null : state.trail.last;
      var next = state;
      if (last == null || _moved(last, location)) {
        next = next.appendPoint(location);
      } else {
        next = next.copyWith(latest: location, loading: false);
      }
      state = next;
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
    }
  }

  void applyPush(LatestLocation location) {
    if (location.lng == 0 && location.lat == 0) {
      // (0,0) 是"空岛"，出现它一定是设备还没定上位，
      // 直接忽略比在地图上把老人画到西非海岸要好
      return;
    }
    final last = state.trail.isEmpty ? null : state.trail.last;
    if (last == null || _moved(last, location)) {
      state = state.appendPoint(location);
    } else {
      state = state.copyWith(latest: location);
    }
  }

  void reset() => state = const LocationState();

  /// 位移是否超过阈值（3 米）。
  bool _moved(TrailPoint from, LatestLocation to) {
    const metersPerDegreeLat = 111320.0;
    final dy = (to.lat - from.lat) * metersPerDegreeLat;
    final dx = (to.lng - from.lng) *
        metersPerDegreeLat *
        math.cos(from.lat * math.pi / 180);
    return math.sqrt(dx * dx + dy * dy) >= 3.0;
  }
}

final locationProvider =
    NotifierProvider<LocationNotifier, LocationState>(LocationNotifier.new);
