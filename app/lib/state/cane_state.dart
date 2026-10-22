import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ble/ble_protocol.dart';
import '../core/ble/cane_connection.dart';
import '../core/ble/mock_cane_connection.dart';
import '../core/ble/real_cane_connection.dart';
import '../core/ws/ws_client.dart';
import '../models/device_info.dart';
import '../models/ward.dart';
import 'providers.dart';
import 'ward_state.dart';
import 'ws_bridge.dart';

/// 手杖数据来源。
enum CaneSource {
  /// 真机：手机作为 BLE 中心直连 ESP32-S3 手杖。
  real,

  /// 模拟：本机扮演手杖，用于无硬件演示。
  mock,
}

/// 在没有显式选择时的默认来源。
///
/// 移动端默认走真机 —— 这是项目的主线场景；
/// Web 与桌面端默认走模拟，因为浏览器要求 HTTPS + 用户手势才能申请蓝牙，
/// 桌面端插件支持情况也参差，默认置真会让用户一进页面就撞上异常。
CaneSource defaultCaneSource() {
  if (kIsWeb) {
    return CaneSource.mock;
  }
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    return CaneSource.real;
  }
  return CaneSource.mock;
}

/// 会话状态：一次性把界面上要用的东西都摊平。
class CaneSessionState {
  const CaneSessionState({
    required this.source,
    this.link = CaneLinkState.idle,
    this.bleAddress,
    this.rssi,
    this.latest,
    this.frameCount = 0,
    this.scanResults = const [],
    this.scanning = false,
    this.connecting = false,
    this.error,
    this.commandHint,
    this.forwardedCount = 0,
    this.droppedCount = 0,
    this.lastForwardedAt,
  });

  final CaneSource source;

  /// BLE 链路状态。
  final CaneLinkState link;
  final String? bleAddress;
  final int? rssi;

  /// 最新一帧（纯本地，不经过云端）。
  final CaneTelemetry? latest;

  /// 本次连接内收到的帧数，用来证明「数据在动」。
  final int frameCount;

  final List<DiscoveredCane> scanResults;
  final bool scanning;
  final bool connecting;

  /// 最近一次失败原因。
  final String? error;

  /// 命令链路的进度提示（已下发 / 执行中 / 执行结果）。
  final String? commandHint;

  /// 已成功转发到云端的帧数。
  final int forwardedCount;

  /// 被后端节流丢弃的帧数。稳态下这个数会持续增长 —— 它是节流在起作用的证据，
  /// 不是故障。
  final int droppedCount;

  final DateTime? lastForwardedAt;

  bool get connected => link == CaneLinkState.connected;
  bool get busy => scanning || connecting;

  /// 链路已建立但还没收到任何一帧 —— 服务发现成功但 TX 没在推数据。
  /// 这是真机上会遇到的一种"连着但没数据"，值得单独提示。
  bool get connectedButSilent => connected && latest == null;

  CaneSessionState copyWith({
    CaneSource? source,
    CaneLinkState? link,
    String? bleAddress,
    int? rssi,
    CaneTelemetry? latest,
    int? frameCount,
    List<DiscoveredCane>? scanResults,
    bool? scanning,
    bool? connecting,
    String? error,
    bool clearError = false,
    String? commandHint,
    bool clearCommandHint = false,
    int? forwardedCount,
    int? droppedCount,
    DateTime? lastForwardedAt,
  }) {
    return CaneSessionState(
      source: source ?? this.source,
      link: link ?? this.link,
      bleAddress: bleAddress ?? this.bleAddress,
      rssi: rssi ?? this.rssi,
      latest: latest ?? this.latest,
      frameCount: frameCount ?? this.frameCount,
      scanResults: scanResults ?? this.scanResults,
      scanning: scanning ?? this.scanning,
      connecting: connecting ?? this.connecting,
      error: clearError ? null : (error ?? this.error),
      commandHint:
          clearCommandHint ? null : (commandHint ?? this.commandHint),
      forwardedCount: forwardedCount ?? this.forwardedCount,
      droppedCount: droppedCount ?? this.droppedCount,
      lastForwardedAt: lastForwardedAt ?? this.lastForwardedAt,
    );
  }
}

/// 手杖会话：BLE 链路的唯一管理者。
///
/// 它把三件事串成一条链：
/// 1. **上行**：解析 TX 通知 → 本机节流 → HTTP 转发到后端；
/// 2. **下行**：订阅 STOMP 命令 → 写入 RX 特征 → 回执 `/command/ack`；
/// 3. **链路状态**：连/断事件显式上报，让云端能立刻把过期的障碍状态标记为失效。
///
/// 本机节流与服务端节流是两层不同的东西，都在起作用：
/// 手杖 500ms 一帧 = 2 帧/秒；本机把它压到「状态变化即发 + 距离跳变 ≥20cm + 30 秒心跳」，
/// 服务端再用 1 秒窗口兜一道 —— 即使某个客户端版本节流有 bug，
/// 云端写入量也不会失控。
class CaneSessionNotifier extends Notifier<CaneSessionState> {
  /// 心跳间隔：稳态下每 30 秒至少转发一帧，
  /// 让云端能持续刷新 last_online_at（否则设备会被判离线）。
  static const Duration _heartbeatInterval = Duration(seconds: 30);

  /// 距离跳变阈值：变化超过这个幅度就立刻转发。
  /// 取 20cm 是因为它跨过了 DANGER/NEAR 之外仍有意义的区间 ——
  /// 界面上的数字肉眼可见地在变，云端记录也该跟上，
  /// 否则家属回看历史时会觉得数据「卡住了」。
  static const int _distanceJumpCm = 20;

  CaneConnection? _connection;
  StreamSubscription<CaneTelemetry>? _telemetrySub;
  StreamSubscription<CaneLinkState>? _linkSub;
  StreamSubscription<DeviceCommandMessage>? _commandSub;

  /// 是否已向后端上报过「链路已连接」。用它去重，避免重复上报，
  /// 也避免 MockCaneConnection 那种「connected 后紧跟 idle」的抖动被误判为断连。
  bool _linkReported = false;

  CaneTelemetry? _lastForwarded;
  DateTime? _lastForwardAt;

  @override
  CaneSessionState build() {
    final source = defaultCaneSource();
    ref.onDispose(_teardown);

    _attach(source);

    // 命令下行：同 ward 下所有家属端都会收到，只有真正持有 BLE 链路的那台去执行
    _commandSub = ref.read(wsClientProvider).commands.listen(_onCommand);
    ref.onDispose(() => _commandSub?.cancel());

    // 换被监护人或换设备后要重新向云端确认链路归属
    ref.listen<int?>(selectedWardIdProvider, (previous, next) {
      if (previous == next) {
        return;
      }
      _linkReported = false;
      unawaited(_syncLinkToBackend());
    });

    return CaneSessionState(source: source);
  }

  // ---------------- 对外操作 ----------------

  /// 切换数据来源。会断开当前链路并按新来源重建。
  void setSource(CaneSource source) {
    if (state.source == source) {
      return;
    }
    _teardown();
    _linkReported = false;
    _lastForwarded = null;
    _lastForwardAt = null;
    _attach(source);
    _apply(state.copyWith(
      source: source,
      link: CaneLinkState.idle,
      latest: null,
      frameCount: 0,
      scanResults: const [],
      clearError: true,
      clearCommandHint: true,
    ));
  }

  /// 扫描附近手杖。
  ///
  /// 模拟模式下优先问后端要列表：后端能看到哪些广播已经登记过设备档案
  /// （带 deviceId / deviceSn / bound），这是本地扫描拿不到的信息。
  /// 后端不可用时退回本地模拟扫描，保证离线也能演示。
  Future<void> scan() async {
    if (state.busy) {
      return;
    }
    _apply(state.copyWith(scanning: true, clearError: true));
    try {
      List<DiscoveredCane> results;
      if (state.source == CaneSource.mock) {
        results = await _scanMock();
      } else {
        results = await _connection?.scan(timeout: const Duration(seconds: 8)) ??
            const <DiscoveredCane>[];
      }
      _apply(state.copyWith(scanResults: results, scanning: false));
    } catch (e) {
      _apply(state.copyWith(scanning: false, error: '扫描失败：$e'));
    }
  }

  Future<List<DiscoveredCane>> _scanMock() async {
    try {
      return await ref.read(repositoryProvider).mockBleScan();
    } catch (e) {
      debugPrint('[Cane] 后端模拟扫描不可用，退回本地模拟：$e');
      return await _connection?.scan(timeout: const Duration(seconds: 2)) ??
          const <DiscoveredCane>[];
    }
  }

  /// 连接手杖。[bleAddress] 来自扫描结果或已登记的设备档案。
  Future<bool> connect(String bleAddress) async {
    final connection = _connection;
    if (connection == null || state.connecting) {
      return false;
    }
    _apply(state.copyWith(
      connecting: true,
      bleAddress: bleAddress,
      clearError: true,
      clearCommandHint: true,
    ));
    final ok = await connection.connect(bleAddress);
    if (!ok) {
      _apply(state.copyWith(
        connecting: false,
        error: connection.lastError ?? '连接失败',
      ));
      return false;
    }
    _apply(state.copyWith(
      connecting: false,
      rssi: connection.rssi,
      clearError: true,
    ));
    // 连上就把地址记到云端：iOS 的地址是随手机随机生成的，
    // 换机后不重新登记，下次自动重连永远匹配不上
    unawaited(_rememberAddress(bleAddress));
    return true;
  }

  Future<void> disconnect() async {
    await _connection?.disconnect();
  }

  /// 切换手杖静音模式（家属侧按钮）。
  ///
  /// 注意这条链路是**绕一圈**的：本接口只把命令下发给后端，
  /// 后端广播到 ward 主题，再由本机（因为持有 BLE 链路）写入 RX 特征，
  /// 最后用 `/command/ack` 提交状态。所以这里刻意**不改任何设备状态** ——
  /// 手杖是不是真的静音了，只有写完特征才知道。
  Future<void> toggleMute() async {
    final deviceId = _currentDeviceId();
    if (deviceId == null) {
      _apply(state.copyWith(error: '尚未绑定导盲杖，无法下发命令'));
      return;
    }
    if (!state.connected) {
      _apply(state.copyWith(error: '请先连接手杖，命令需要通过手机转发'));
      return;
    }
    // WebSocket 断开时命令根本回不到本机，直接告诉用户比让他干等有用
    if (ref.read(wsStatusProvider) != WsStatus.connected) {
      _apply(state.copyWith(error: '实时通道已断开，命令无法下发，请稍后重试'));
      return;
    }
    try {
      final message = await ref.read(repositoryProvider).issueCommand(
            deviceId: deviceId,
            command: BleProtocol.cmdToggleMute,
          );
      _apply(state.copyWith(
        commandHint: '已下发「${message.commandName ?? message.command}」，等待手杖执行…',
        clearError: true,
      ));
    } catch (e) {
      _apply(state.copyWith(error: '命令下发失败：$e'));
    }
  }

  /// 清掉一次性提示（用户已读）。
  void acknowledgeHint() {
    _apply(state.copyWith(clearError: true, clearCommandHint: true));
  }

  // ---------------- 内部：链路与数据流 ----------------

  void _attach(CaneSource source) {
    final connection = source == CaneSource.real
        ? RealCaneConnection()
        : MockCaneConnection();
    _connection = connection;
    _linkSub = connection.linkStates.listen(_onLinkState);
    _telemetrySub = connection.telemetry.listen(_onTelemetry);
  }

  void _teardown() {
    _linkSub?.cancel();
    _linkSub = null;
    _telemetrySub?.cancel();
    _telemetrySub = null;
    final connection = _connection;
    _connection = null;
    unawaited(connection?.dispose());
  }

  void _onLinkState(CaneLinkState next) {
    switch (next) {
      case CaneLinkState.connected:
        _apply(state.copyWith(
          link: next,
          rssi: _connection?.rssi,
          clearError: true,
        ));
        unawaited(_syncLinkToBackend());
      case CaneLinkState.disconnected:
      case CaneLinkState.idle:
        // 只在「本来已连接」时才当成断连处理。
        // Mock 断开时会先发 disconnected 再发 idle，且初始态也是 idle，
        // 不加这个判断会把启动瞬间误报成一次断连
        if (_linkReported || state.connected) {
          _apply(state.copyWith(link: CaneLinkState.disconnected));
          unawaited(_syncLinkToBackend());
        }
      case CaneLinkState.connecting:
        _apply(state.copyWith(link: next));
      case CaneLinkState.scanning:
        // 扫描不影响链路，忽略
        break;
    }
  }

  void _onTelemetry(CaneTelemetry frame) {
    _apply(state.copyWith(
      latest: frame,
      frameCount: state.frameCount + 1,
      // 一旦收到数据就说明链路是真的通了，顺手清掉上一次的连接错误
      clearError: true,
    ));

    final deviceId = _currentDeviceId();
    if (deviceId == null) {
      return;
    }
    if (!_shouldForward(frame)) {
      return;
    }
    unawaited(_forward(deviceId, frame));
  }

  bool _shouldForward(CaneTelemetry frame) {
    final last = _lastForwarded;
    if (last == null) {
      return true;
    }
    // 1) 状态变化 —— 危险必须零延迟可见，不能被节流耽误
    if (last.status != frame.status) {
      return true;
    }
    // 2) 距离跳变
    final previous = last.distanceCm;
    final current = frame.distanceCm;
    if (previous != null &&
        current != null &&
        (previous - current).abs() >= _distanceJumpCm) {
      return true;
    }
    // 3) 心跳：维持设备在线判定，同时保证云端有新鲜读数
    final at = _lastForwardAt;
    if (at == null) {
      return true;
    }
    return DateTime.now().difference(at) >= _heartbeatInterval;
  }

  Future<void> _forward(int deviceId, CaneTelemetry frame) async {
    // 先打点再发请求：如果失败，也不该在下一帧立刻重发同样内容 ——
    // 那会让节流退化成"每帧都发"，正是要避免的事
    _lastForwarded = frame;
    _lastForwardAt = DateTime.now();
    try {
      final ack = await ref.read(repositoryProvider).reportTelemetry(
            deviceId: deviceId,
            status: frame.status.name.toUpperCase(),
            distanceCm: frame.distanceCm,
            battery: frame.battery,
            rssi: _connection?.rssi,
          );
      if (ack.accepted) {
        _apply(state.copyWith(
          forwardedCount: state.forwardedCount + 1,
          lastForwardedAt: DateTime.now(),
        ));
      } else {
        // 被服务端节流丢弃是正常现象（稳态下每 2 帧丢 1 帧），不是错误。
        // 这里只计数，供"节流生效"的说明用
        _apply(state.copyWith(
          droppedCount: state.droppedCount + 1,
          lastForwardedAt: DateTime.now(),
        ));
      }
    } catch (e) {
      _apply(state.copyWith(error: '遥测上报失败：$e'));
    }
  }

  /// 把当前链路状态同步给云端。
  ///
  /// 幂等：靠 [_linkReported] 与 `state.connected` 双重判断，
  /// 只在「云端认知」与「实际链路」不一致时才发请求。
  Future<void> _syncLinkToBackend() async {
    final deviceId = _currentDeviceId();
    if (deviceId == null) {
      return;
    }
    final actuallyConnected = state.connected;
    if (actuallyConnected == _linkReported) {
      return;
    }
    _linkReported = actuallyConnected;
    try {
      final device = await ref.read(repositoryProvider).reportBleLink(
            deviceId: deviceId,
            connected: actuallyConnected,
            rssi: _connection?.rssi,
          );
      ref.read(liveDeviceProvider.notifier).apply(device);
    } catch (e) {
      // 上报失败就把标记回滚，下次事件再试
      _linkReported = !actuallyConnected;
      _apply(state.copyWith(error: '蓝牙链路状态上报失败：$e'));
    }
  }

  void _onCommand(DeviceCommandMessage message) {
    final deviceId = _currentDeviceId();
    if (deviceId == null || message.deviceId != deviceId) {
      return;
    }
    if (!state.connected) {
      // 本机没有链路，说明命令该由另一台手机执行。
      // 这里**不能回执成功或失败** —— 回执是状态的唯一提交点，
      // 无链路的一方抢答会把真正执行的那台手机的结果覆盖掉
      _apply(state.copyWith(
        commandHint: '收到命令「${message.commandName ?? message.command}」，'
            '但本机未连接手杖，未执行',
      ));
      return;
    }
    unawaited(_executeCommand(deviceId, message));
  }

  Future<void> _executeCommand(int deviceId, DeviceCommandMessage message) async {
    final connection = _connection;
    if (connection == null) {
      return;
    }
    _apply(state.copyWith(
      commandHint: '正在执行「${message.commandName ?? message.command}」…',
    ));
    final ok = await connection.sendCommand(message.command);
    final detail = ok ? null : (connection.lastError ?? '写入 RX 特征失败');

    try {
      final device = await ref.read(repositoryProvider).ackCommand(
            deviceId: deviceId,
            command: message.command,
            success: ok,
            detail: detail,
          );
      // 用回执返回的权威状态覆盖本地显示，纠正等待期间可能已做的乐观显示
      ref.read(liveDeviceProvider.notifier).apply(device);
      _apply(state.copyWith(
        commandHint: ok
            ? '「${message.commandName ?? message.command}」已执行，'
                '手杖当前${device.muted ? '静音' : '播报'}'
            : '命令执行失败：$detail',
        clearError: true,
      ));
    } catch (e) {
      _apply(state.copyWith(
        commandHint: ok
            ? '命令已执行，但回执上报失败：$e（云端状态可能未更新）'
            : '命令执行失败：$detail；回执上报也失败：$e',
      ));
    }
  }

  /// 把这次连接的地址写回云端档案，供下次自动重连使用。
  Future<void> _rememberAddress(String bleAddress) async {
    final deviceId = _currentDeviceId();
    if (deviceId == null) {
      return;
    }
    final known = ref.read(liveDeviceProvider)?.bleAddress ??
        ref.read(currentWardProvider)?.device?.bleAddress;
    if (known != null && known.toUpperCase() == bleAddress.toUpperCase()) {
      return;
    }
    try {
      final device = await ref.read(repositoryProvider).bindBleAddress(
            deviceId: deviceId,
            bleAddress: bleAddress,
          );
      ref.read(liveDeviceProvider.notifier).apply(device);
      debugPrint('[Cane] 已更新手杖蓝牙地址: $bleAddress');
    } catch (e) {
      // 地址冲突（104006）或网络问题都不阻塞连接本身：
      // 本次会话已经通了，只是下次自动重连还需要重新扫
      debugPrint('[Cane] 蓝牙地址登记失败（不影响本次连接）: $e');
    }
  }

  /// 当前 ward 的设备 id。优先用实时状态，回退到列表快照。
  int? _currentDeviceId() {
    final live = ref.read(liveDeviceProvider);
    if (live != null) {
      return live.id;
    }
    return ref.read(currentWardProvider)?.device?.id;
  }

  void _apply(CaneSessionState next) {
    state = next;
  }
}

final caneSessionProvider =
    NotifierProvider<CaneSessionNotifier, CaneSessionState>(
        CaneSessionNotifier.new);

/// 当前 ward 的设备信息（实时优先）。
///
/// 单独抽出来是为了让界面只 watch 一个 provider —— 否则每个用到设备的
/// 组件都要写一遍 `liveDeviceProvider ?? currentWard.device`，
/// 一旦优先级变了就得改很多处。
final caneTargetDeviceProvider = Provider<DeviceInfo?>((ref) {
  final live = ref.watch(liveDeviceProvider);
  if (live != null) {
    return live;
  }
  final Ward? ward = ref.watch(currentWardProvider);
  return ward?.device;
});
