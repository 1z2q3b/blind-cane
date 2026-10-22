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
    final store = ref.read(tokenStoreProvider);

    if (wards.isEmpty) {
      // 关键：一个档案都不剩时必须把本地的 currentWardId 抹掉。
      // 否则它会一直指向一个已经被删除的 id，首页、位置轮询、告警都会
      // 拿着这个 id 去请求，然后被后端一路 103001 拒绝——
      // 表现就是"删完档案之后到处都在报无监护权限"。
      if (store.currentWardId != null) {
        // 只清持久化，不在这里改 selectedWardIdProvider：
        // 在 build 期间（哪怕是微任务里）改别的 provider 会触发 layout 重入，
        // Flutter 的 assert(!_debugDoingThisLayout) 会直接炸掉整棵树。
        // 内存态由 SelectedWardNotifier.build 自己按列表有效性判断。
        await store.setCurrentWardId(null);
      }
      return wards;
    }

    // 首次拿到数据后，若还没选过被监护人，默认选第一个：
    // 家属通常只监护一个人，多一步选择只是多余操作。
    final current = store.currentWardId;
    if (current == null || !wards.any((w) => w.id == current)) {
      await store.setCurrentWardId(wards.first.id);
      _selectedId = wards.first.id;
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
    double? homeLng,
    double? homeLat,
    String? contactPhone,
    String? medicalNotes,
  }) async {
    final detail = await ref.read(repositoryProvider).createWard(
          name: name,
          relation: relation,
          birthYear: birthYear,
          homeAddress: homeAddress,
          homeLng: homeLng,
          homeLat: homeLat,
          contactPhone: contactPhone,
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
    double? homeLng,
    double? homeLat,
    String? contactPhone,
    String? medicalNotes,
  }) async {
    final detail = await ref.read(repositoryProvider).updateWard(
          wardId: wardId,
          name: name,
          relation: relation,
          birthYear: birthYear,
          homeAddress: homeAddress,
          homeLng: homeLng,
          homeLat: homeLat,
          contactPhone: contactPhone,
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

  /// 删除档案。
  ///
  /// 服务端会把该档案的围栏、轨迹、告警一起清掉并解绑设备，所以本地只需三件事：
  /// 作废详情缓存、把选中态从已删除的 id 上移开、刷新列表。
  /// 漏掉选中态那步的后果是：本地还记着一个不存在的 wardId，首页所有请求都会 404。
  Future<void> remove(int wardId) async {
    await ref.read(repositoryProvider).deleteWard(wardId);
    ref.invalidate(wardDetailProvider(wardId));

    if (ref.read(selectedWardIdProvider) == wardId) {
      await ref.read(selectedWardIdProvider.notifier).select(null);
    }

    await refresh();

    // 删完之后如果还有别的档案，自动选第一个，别让首页停在"未选择"的空态
    final rest = state.value ?? const [];
    if (ref.read(selectedWardIdProvider) == null && rest.isNotEmpty) {
      await ref.read(selectedWardIdProvider.notifier).select(rest.first.id);
    }
  }
}

final wardListProvider =
    AsyncNotifierProvider<WardListNotifier, List<Ward>>(WardListNotifier.new);

/// 当前选中的被监护人 id，持久化到本地。
class SelectedWardNotifier extends Notifier<int?> {
  @override
  int? build() {
    final stored = ref.watch(tokenStoreProvider).currentWardId;
    final wards = ref.watch(wardListProvider).asData?.value;
    // 列表已经拿到、但存的 id 不在里面（档案被删了）→ 视为未选中。
    // 用声明式判断，而不是在其他地方 setState 去改：删除档案后如果在
    // build/layout 期间改这个 provider，会触发 Flutter 的布局重入断言，
    // 整个界面直接白屏。这里是纯读计算，不会产生这种副作用。
    if (wards != null && (wards.isEmpty || !wards.any((w) => w.id == stored))) {
      return null;
    }
    return stored;
  }

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
  // asData 而不是 value：value 在 error 态会把异常重新抛出来，
  // 而这个 provider 被首页等大量 Widget watch，一旦抛出就是整页白屏
  final wards = ref.watch(wardListProvider).asData?.value;
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
  /// 后端 `/device` 主题的载荷刻意保持精简（online/battery/signalLevel/bleConnected/
  /// obstacle*），如果直接用推送覆盖整个对象，`deviceSn`、`firmwareVersion`、
  /// `bleAddress` 这些只来自 REST 的字段会被清空，界面上就会突然出现空白。
  ///
  /// 障碍字段的处理要特别小心：推送里 `bleConnected=false` 时
  /// `obstacleStatus` 虽然还有值，但那是「断开前的最后读数」。
  /// 这里如实存下来，由界面按 [DeviceInfo.hasLiveObstacle] 决定怎么显示 ——
  /// 直接把它抹成 null 会丢掉「最后状态」这个有用信息。
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
      bleAddress: current.bleAddress,
      bleConnected: message.bleConnected,
      bleConnectedAt: message.bleConnected != current.bleConnected
          ? DateTime.now()
          : current.bleConnectedAt,
      // 断开时后端已把 bleRssi 置空，这里同步成 null，
      // 否则会显示「蓝牙已断开 · 信号 -57dBm」这种自相矛盾的组合
      bleRssi: message.bleConnected ? current.bleRssi : null,
      obstacleStatus: message.obstacleStatus ?? current.obstacleStatus,
      obstacleDistanceCm:
          message.obstacleDistanceCm ?? current.obstacleDistanceCm,
      obstacleReportedAt:
          message.obstacleReportedAt ?? current.obstacleReportedAt,
      obstacleSeconds: message.obstacleReportedAt == null
          ? current.obstacleSeconds
          : DateTime.now().difference(message.obstacleReportedAt!).inSeconds,
      muteMode: message.muteMode ?? current.muteMode,
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
