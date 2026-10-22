import 'dart:async';

import 'ble_protocol.dart';
import 'cane_connection.dart';

/// 模拟手杖：扮演「ESP32-S3 + HC-SR04」那一端。
///
/// 存在的理由很实际 —— 手杖在实验室、在充电、在别人手上，而演示与联调
/// 随时都要跑。这个类按规格把 `CLEAR/NEAR/DANGER` 三种状态循环推出来，
/// 帧格式与真机逐字节一致（`<状态>,<距离cm>`，UTF-8），
/// 因此上层解析器、节流逻辑、命令回执全部走真实代码路径，
/// 唯一被替换掉的只有「射频」这一段。
///
/// 一个循环 40 帧：30 帧畅通 → 6 帧有障碍 → 4 帧危险 → 回到畅通。
/// 这样安排是因为真实使用中畅通占绝大多数时间，
/// 而演示需要在十几秒内把三种状态都露一遍。
class MockCaneConnection implements CaneConnection {
  MockCaneConnection({this.interval = const Duration(milliseconds: 500)});

  /// 帧间隔。真机是 500ms，测试里会调到 5ms 以便快速跑完一整个循环。
  final Duration interval;

  /// 模拟手杖的蓝牙地址。
  ///
  /// 与后端 `blindcane.simulator.demo-ble-address` 的默认值一致 ——
  /// 这样「后端 Mock 扫描列表」与「本机模拟连接」指向同一个地址，
  /// 演示时不会出现扫到 A 却连到 B 的错位。
  static const String mockAddress = 'D0:CF:13:8A:00:01';

  final _telemetryCtrl = StreamController<CaneTelemetry>.broadcast();
  final _linkCtrl = StreamController<CaneLinkState>.broadcast();

  Timer? _timer;
  int _frameIndex = 0;
  bool _muted = false;
  int? _rssi;
  String? _address;
  CaneLinkState _state = CaneLinkState.idle;
  String? _lastError;

  @override
  Stream<CaneTelemetry> get telemetry => _telemetryCtrl.stream;

  @override
  Stream<CaneLinkState> get linkStates => _linkCtrl.stream;

  @override
  CaneLinkState get state => _state;

  @override
  String? get lastError => _lastError;

  @override
  bool get muted => _muted;

  @override
  int? get rssi => _rssi;

  @override
  String? get connectedAddress => _address;

  @override
  Future<List<DiscoveredCane>> scan({Duration timeout = const Duration(seconds: 8)}) async {
    _emitLink(CaneLinkState.scanning);
    // 模拟一点扫描耗时，让界面上的"扫描中"不是一闪而过 ——
    // 否则演示时看不清这个状态，反而会以为功能没反应
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _emitLink(_state == CaneLinkState.connected
        ? CaneLinkState.connected
        : CaneLinkState.idle);
    return const [
      DiscoveredCane(
        bleAddress: mockAddress,
        name: BleProtocol.deviceName,
        rssi: -58,
        // registered=false：这台"手杖"在云端还没有设备档案，
        // 界面会引导用户按 SN 走一次绑定，而不是直接连接
        registered: false,
      ),
    ];
  }

  @override
  Future<bool> connect(String bleAddress) async {
    _emitLink(CaneLinkState.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _address = bleAddress;
    _rssi = -58;
    _frameIndex = 0;
    _muted = false;
    _lastError = null;
    _emitLink(CaneLinkState.connected);
    _startPushing();
    return true;
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
    _address = null;
    _rssi = null;
    _emitLink(CaneLinkState.disconnected);
    _emitLink(CaneLinkState.idle);
  }

  @override
  Future<bool> sendCommand(String command) async {
    if (_state != CaneLinkState.connected) {
      _lastError = '模拟手杖未连接';
      return false;
    }
    // 只实现规格里已有的命令。预留命令返回 false 而不是"假装成功" ——
    // 后者会让上层的回执提交点失去意义，把一个真问题藏起来
    if (command == BleProtocol.cmdToggleMute) {
      _muted = !_muted;
      return true;
    }
    _lastError = '模拟手杖不支持命令 $command';
    return false;
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _telemetryCtrl.close();
    await _linkCtrl.close();
  }

  // ------------------------------------------------------------------

  void _startPushing() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _pushFrame());
  }

  void _pushFrame() {
    if (_state != CaneLinkState.connected || _telemetryCtrl.isClosed) {
      return;
    }
    final distance = _distanceOf(_frameIndex % _cycleLength);
    _frameIndex++;
    final status = ObstacleStatus.fromDistance(distance);
    // 帧格式与固件完全一致：大写状态 + 逗号 + 距离，UTF-8
    final raw = '${status.name.toUpperCase()},$distance';
    final frame = CaneTelemetry.tryParse(raw);
    if (frame != null) {
      _telemetryCtrl.add(frame);
    }
  }

  /// 一个循环的帧数。
  static const int _cycleLength = 40;

  /// 循环内第 [index] 帧的距离（cm）。
  static int _distanceOf(int index) {
    if (index < 30) {
      // 畅通段：235 → 148，逐步靠近但仍远在 100cm 之外
      return 235 - index * 3;
    }
    if (index < 36) {
      // 有障碍段：20~100cm，从远到近
      return const [95, 80, 66, 52, 40, 28][index - 30];
    }
    // 危险段：<20cm，最小 8cm。
    // 下限取 8 而不是 1~2：真机在贴到对象时读数会抖，
    // 演示时显示"危险 8cm"比"危险 1cm"更容易让人相信这是真实测距
    return const [18, 14, 11, 8][index - 36];
  }

  void _emitLink(CaneLinkState state) {
    _state = state;
    if (!_linkCtrl.isClosed) {
      _linkCtrl.add(state);
    }
  }
}
