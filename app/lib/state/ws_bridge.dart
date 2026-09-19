import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ws/ws_client.dart';
import '../models/ward.dart';
import 'alert_state.dart';
import 'location_state.dart';
import 'providers.dart';
import 'ward_state.dart';

/// WebSocket 连接状态（供 UI 展示"实时连接中 / 已断开"）。
class WsStatusNotifier extends Notifier<WsStatus> {
  @override
  WsStatus build() => WsStatus.idle;

  void set(WsStatus status) => state = status;
}

final wsStatusProvider =
    NotifierProvider<WsStatusNotifier, WsStatus>(WsStatusNotifier.new);

/// 把 WebSocket 推送、被监护人切换、轮询兜底这三件事接起来的桥。
///
/// 单独抽一层而不是让各页面自己去监听推送，原因很实际：
/// 位置推送要同时更新「实时位置」「本地轨迹」两个状态，告警推送要更新
/// 「列表」「角标」「全屏提醒」三处。如果分别在页面里订阅，
/// 页面一关推送就没人处理了——家属切到设置页时告警就不弹了，这不可接受。
/// 放在这里，只要 App 活着就一直在工作。
final wsBridgeProvider = Provider<WsBridge>((ref) {
  final bridge = WsBridge(ref);
  // 不能同步 start()：start() 会在构建期间（_switchWard → reset/clear）直接修改
  // locationProvider / liveDeviceProvider 等其他 provider 的 state，触发 Riverpod
  // 「Providers are not allowed to modify other providers during their initialization」断言，
  // 登录进首页那一刻就是整屏红字。延迟到本帧同步段结束后再启动，
  // 届时 wsBridgeProvider 已 mounted，不再是 build 期间。
  Future.microtask(bridge.start);
  ref.onDispose(bridge.dispose);
  return bridge;
});

class WsBridge {
  WsBridge(this._ref);

  final Ref _ref;
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _pollTimer;
  int? _connectedWardId;

  void start() {
    final ws = _ref.read(wsClientProvider);

    _subs.add(ws.statuses.listen((status) {
      _ref.read(wsStatusProvider.notifier).set(status);
      if (status == WsStatus.connected) {
        // 断线期间的推送会丢，重连成功后立刻拉一次全量最新数据补上
        _reloadCurrentWard();
      }
    }));

    _subs.add(ws.locations.listen((location) {
      _ref.read(locationProvider.notifier).applyPush(location);
    }));

    _subs.add(ws.deviceStatuses.listen((status) {
      _ref.read(liveDeviceProvider.notifier).applyStatus(status);
      // 在线状态翻转时电量可能也变了，但推送里已带电量，无需再查
    }));

    _subs.add(ws.alerts.listen((alert) {
      _ref.read(alertListProvider.notifier).prependFromPush(alert);
      if (alert.isPending) {
        _ref.read(pendingCountProvider.notifier).increase(alert.wardId);
      }
      _ref.read(fullScreenAlertProvider.notifier).push(alert);
    }));

    // 被监护人切换：换订阅 + 重新拉一次该 ward 的位置与设备
    _ref.listen<int?>(selectedWardIdProvider, (previous, next) {
      if (previous == next) {
        return;
      }
      _connectedWardId = null;
      _switchWard(next);
    });

    // 设备变化（建档绑定 / 解绑）后刷新设备状态
    _ref.listen<Ward?>(currentWardProvider, (previous, next) {
      if (previous?.device?.id == next?.device?.id) {
        return;
      }
      _loadDevice(next);
    });

    // 初始进入
    _switchWard(_ref.read(selectedWardIdProvider));

    // 轮询兜底：WebSocket 断开时保证家属仍能看到最新数据（提示词 7.3 的降级策略）。
    // 连接正常时不轮询，避免和推送重复请求。
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_ref.read(wsStatusProvider) != WsStatus.connected) {
        debugPrint('[WsBridge] WebSocket 未连接，轮询兜底刷新');
        _reloadCurrentWard();
      }
    });
  }

  void _switchWard(int? wardId) {
    if (wardId == null) {
      _ref.read(wsClientProvider).disconnect();
      _ref.read(locationProvider.notifier).reset();
      _ref.read(liveDeviceProvider.notifier).clear();
      return;
    }
    if (_connectedWardId == wardId) {
      return;
    }
    _connectedWardId = wardId;
    _ref.read(locationProvider.notifier).reset();
    _ref.read(wsClientProvider).connect(wardId);
    _ref.read(locationProvider.notifier).load(wardId);
    _loadDevice(_ref.read(currentWardProvider));
    _ref.read(pendingCountProvider.notifier).refresh();
  }

  void _reloadCurrentWard() {
    final wardId = _ref.read(selectedWardIdProvider);
    if (wardId == null) {
      return;
    }
    _ref.read(locationProvider.notifier).load(wardId);
    _loadDevice(_ref.read(currentWardProvider));
    _ref.read(pendingCountProvider.notifier).refresh();
  }

  void _loadDevice(Ward? ward) {
    final deviceId = ward?.device?.id;
    if (deviceId == null) {
      _ref.read(liveDeviceProvider.notifier).clear();
      return;
    }
    _ref.read(liveDeviceProvider.notifier).load(deviceId);
  }

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
  }
}
