import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/geofence.dart';
import 'providers.dart';
import 'ward_state.dart';

/// 当前被监护人的围栏列表。
///
/// 跟着 [selectedWardIdProvider] 走：家属在首页切换被监护人后，围栏列表自动跟着换，
/// 页面不需要自己监听切换事件。
class GeofenceListNotifier extends AsyncNotifier<List<Geofence>> {
  @override
  Future<List<Geofence>> build() async {
    final wardId = ref.watch(selectedWardIdProvider);
    if (wardId == null) {
      return const [];
    }
    return ref.read(repositoryProvider).listGeofences(wardId);
  }

  Future<void> refresh() async {
    final wardId = ref.read(selectedWardIdProvider);
    if (wardId == null) {
      state = const AsyncValue.data([]);
      return;
    }
    state = await AsyncValue.guard(
      () => ref.read(repositoryProvider).listGeofences(wardId),
    );
  }

  Future<void> create({
    required String name,
    required double centerLng,
    required double centerLat,
    required int radiusM,
    required int fenceType,
    bool enabled = true,
  }) async {
    final wardId = ref.read(selectedWardIdProvider);
    if (wardId == null) {
      throw StateError('还没有选择被监护人');
    }
    await ref.read(repositoryProvider).createGeofence(
          wardId: wardId,
          name: name,
          centerLng: centerLng,
          centerLat: centerLat,
          radiusM: radiusM,
          fenceType: fenceType,
          enabled: enabled,
        );
    await refresh();
  }

  /// 修改围栏。
  ///
  /// 方法名不能叫 `update`：Riverpod 3.x 的 AsyncNotifier 自带一个
  /// `update(FutureOr<T> Function(T))` 用于按当前值派生新状态，
  /// 同名会把父类方法遮蔽掉并直接编译报错（invalid_override）。
  Future<void> edit(
    int id, {
    String? name,
    double? centerLng,
    double? centerLat,
    int? radiusM,
    int? fenceType,
  }) async {
    await ref.read(repositoryProvider).updateGeofence(
          id: id,
          name: name,
          centerLng: centerLng,
          centerLat: centerLat,
          radiusM: radiusM,
          fenceType: fenceType,
        );
    await refresh();
  }

  Future<void> toggle(int id, bool enabled) async {
    // 先在本地乐观更新，开关会立刻响应；失败再回滚到服务端真实状态。
    // 家属点开关的预期是"马上就生效"，等一个网络往返会有明显的迟滞感。
    final previous = state.value;
    if (previous != null) {
      state = AsyncValue.data([
        for (final fence in previous)
          fence.id == id ? fence.copyWith(enabled: enabled ? 1 : 0) : fence,
      ]);
    }
    try {
      await ref.read(repositoryProvider).setGeofenceEnabled(id, enabled);
    } catch (_) {
      if (previous != null) {
        state = AsyncValue.data(previous);
      }
      rethrow;
    }
  }

  Future<void> remove(int id) async {
    await ref.read(repositoryProvider).deleteGeofence(id);
    await refresh();
  }
}

final geofenceListProvider =
    AsyncNotifierProvider<GeofenceListNotifier, List<Geofence>>(
  GeofenceListNotifier.new,
);

/// 轨迹回放选中的日期（只取日期部分，后端按整天返回）。
///
/// 用 Notifier 而不是 StateProvider：Riverpod 3.x 已把 StateProvider
/// 移到 `flutter_riverpod/legacy.dart`，主入口不再导出，直接写会编译不过。
class TrackDateNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime.now();

  void select(DateTime day) {
    state = day;
  }
}

final trackDateProvider =
    NotifierProvider<TrackDateNotifier, DateTime>(TrackDateNotifier.new);

/// 某一天的轨迹点。
///
/// 与围栏列表一样跟随当前被监护人；日期变化会触发重新查询。
class TrackNotifier extends AsyncNotifier<List<TrackPoint>> {
  @override
  Future<List<TrackPoint>> build() async {
    final wardId = ref.watch(selectedWardIdProvider);
    final day = ref.watch(trackDateProvider);
    if (wardId == null) {
      return const [];
    }
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return ref.read(repositoryProvider).fetchTrack(
          wardId: wardId,
          start: start,
          end: end,
        );
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final wardId = ref.read(selectedWardIdProvider);
      if (wardId == null) {
        return const <TrackPoint>[];
      }
      final day = ref.read(trackDateProvider);
      final start = DateTime(day.year, day.month, day.day);
      return ref.read(repositoryProvider).fetchTrack(
            wardId: wardId,
            start: start,
            end: start.add(const Duration(days: 1)),
          );
    });
  }
}

final trackProvider =
    AsyncNotifierProvider<TrackNotifier, List<TrackPoint>>(TrackNotifier.new);
