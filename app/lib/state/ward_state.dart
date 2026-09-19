import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_response.dart';
import '../core/storage/token_store.dart';
import '../models/device_info.dart';
import '../models/ward.dart';
import 'providers.dart';

/// 被监护人列表（服务端快照）。
///
/// 实时数据（位置 / 设备状态）不放在这里，而是由 WebSocket 单独维护：
/// 若把位置也塞进列表状态，每 10 秒一次的推送都会重建整个列表，
/// 首页上所有卡片连同滚动位置一起抖一下。
class WardListNotifier extends AsyncNotifier<List<Ward>> {
  @override
  Future<List<Ward>> build() async {
    final repository = ref.watch(repositoryProvider);
    final wards = await repository.listWards();
    // 首次拿到数据后，若还没选过被监护人，默认选第一个：
    // 家属通常只监护一个人，多一步选择只是多余操作。
    if (wards.isNotEmpty) {
      final store = ref.read(tokenStoreProvider);
      final current = store.currentWardId;
      if (current == null || !wards.any((w) => w.id == current)) {
        await store.setCurrentWardId(wards.first.id);
        _selectedId = wards.first.id;
      }
    }
    return wards;
  }

  /// build() 里不能直接改别的 provider 状态（会触发"在构建期间修改 provider"异常），
  /// 所以先记在字段里，由 UI 侧首次读取时同步过去。
  int? _selectedId;
  int? consumeInitialSelection() {
    final id = _selectedId;
    _selectedId = null;
    return id;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => ref.read(repositoryProvider).listWards());
  }

  Future<WardDetail> create({
    required String name,
    String? relation,
    int? birthYear,
    String? homeAddress,
    String? medicalNotes,
  }) async {
    final detail = await ref.read(repositoryProvider).createWard(
          name: name,
          relation: relation,
          birthYear: birthYear,
          homeAddress: homeAddress,
          medicalNotes: medicalNotes,
        );
    await refresh();
    return detail;
  }

  Future<WardDetail> updateWard({
    required int wardId,
    required String name,
    String? relation,
    int? birthYear,
    String? homeAddress,
    String? medicalNotes,
  }) async {
    final detail = await ref.read(repositoryProvider).updateWard(
          wardId: wardId,
          name: name,
          relation: relation,
          birthYear: birthYear,
          homeAddress: homeAddress,
          medicalNotes: medicalNotes,
        );
    await refresh();
    return detail;
  }

  Future<void> bindDevice({required String deviceSn, required int wardId}) async {
    await ref.read(repositoryProvider).bindDevice(deviceSn: deviceSn, wardId: wardId);
    await refresh();
  }

  Future<void> unbindDevice(int deviceId) async {
    await ref.read(repositoryProvider).unbindDevice(deviceId);
    await refresh();
  }
}

final wardListProvider =
    AsyncNotifierProvider<WardListNotifier, List<Ward>>(WardListNotifier.new);

/// 当前选中的被监护人 id，持久化到本地。
class SelectedWardNotifier extends Notifier<int?> {
  @override
  int? build() => ref.watch(tokenStoreProvider).currentWardId;

  Future<void> select(int? wardId) async {
    if (state == wardId) {
      return;
    }
    state = wardId;
    await ref.read(tokenStoreProvider).setCurrentWardId(wardId);
  }
}

final selectedWardIdProvider =
    NotifierProvider<SelectedWardNotifier, int?>(SelectedWardNotifier.new);

/// 当前选中的被监护人对象（从列表快照里取）。
final currentWardProvider = Provider<Ward?>((ref) {
  final wards = ref.watch(wardListProvider).value;
  if (wards == null || wards.isEmpty) {
    return null;
  }
  final selected = ref.watch(selectedWardIdProvider);
  if (selected == null) {
    return wards.first;
  }
  return wards.firstWhere(
    (w) => w.id == selected,
    orElse: () => wards.first,
  );
});

/// 被监护人详情（含解密后的病史）。写操作后 `ref.invalidate` 即可刷新。
final wardDetailProvider =
    FutureProvider.family<WardDetail, int>((ref, wardId) async {
  return ref.watch(repositoryProvider).getWard(wardId);
});

/// 设备实时状态（当前被监护人的设备）。
///
/// 由 WebSocket `/device` 主题驱动，REST 只用于首次填充与轮询兜底。
class LiveDeviceNotifier extends Notifier<DeviceInfo?> {
  @override
  DeviceInfo? build() => null;

  void apply(DeviceInfo device) {
    state = device;
  }

  /// 只更新推送里带的那几个字段。
  ///
  /// 后端 `/device` 主题的载荷刻意保持精简（online/battery/signalLevel），
  /// 如果直接用推送覆盖整个对象，`deviceSn`、`firmwareVersion` 这些
  /// 只来自 REST 的字段会被清空，界面上就会突然出现空白。
  void applyStatus(DeviceStatusMessage message) {
    final current = state;
    if (current == null) {
      return;
    }
    state = DeviceInfo(
      id: current.id,
      deviceSn: current.deviceSn,
      name: current.name,
      wardId: current.wardId,
      battery: message.battery ?? current.battery,
      signalLevel: message.signalLevel ?? current.signalLevel,
      online: message.online,
      lastOnlineAt: message.online ? DateTime.now() : current.lastOnlineAt,
      offlineSeconds: message.online ? 0 : current.offlineSeconds,
      firmwareVersion: current.firmwareVersion,
    );
  }

  Future<void> load(int deviceId) async {
    try {
      final device = await ref.read(repositoryProvider).deviceStatus(deviceId);
      state = device;
    } on ApiException {
      // 轮询失败不改变现有状态：偶发网络抖动不该把家属看到的
      // 「在线 · 85%」瞬间变成错误提示。
    }
  }

  void clear() => state = null;
}

final liveDeviceProvider =
    NotifierProvider<LiveDeviceNotifier, DeviceInfo?>(LiveDeviceNotifier.new);
