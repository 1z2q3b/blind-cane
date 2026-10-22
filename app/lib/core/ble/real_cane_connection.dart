import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_protocol.dart';
import 'cane_connection.dart';

/// 真机连接：手机作为 BLE 中心（Central），直连 ESP32-S3 手杖。
///
/// 链路建立的实际步骤（每一步都可能失败，且失败原因完全不同）：
/// 1. 扫描，按广播名 `StarPath` 或 NUS 服务 UUID 认出目标；
/// 2. `connect()` 建立 GATT 连接；
/// 3. `discoverServices()` 拿到服务表；
/// 4. 在 NUS 服务下取 TX（Notify）与 RX（Write）两个特征；
/// 5. 订阅 TX 通知（`setNotifyValue(true)` 会自动写 CCCD）；
/// 6. 之后每 500ms 收到一行 UTF-8 文本。
///
/// 这些失败原因必须被区分开并原样告诉用户：BLE 的异常码本身
/// （133、`servicesNotFound`、权限被拒）在不同机型上含义还不一样，
/// 把原码带上比翻译成一句"连接失败"有用得多。
class RealCaneConnection implements CaneConnection {
  RealCaneConnection();

  final _telemetryCtrl = StreamController<CaneTelemetry>.broadcast();
  final _linkCtrl = StreamController<CaneLinkState>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _valueSub;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _tx;
  BluetoothCharacteristic? _rx;

  CaneLinkState _state = CaneLinkState.idle;
  String? _lastError;
  bool _muted = false;
  int? _rssi;
  String? _address;

  /// 平台是否具备蓝牙能力。Web 需要 HTTPS + 用户手势，桌面端视系统而定，
  /// 界面据此决定是否把"真机"选项置灰，而不是让用户点了之后收到一个异常。
  static Future<bool> isSupported() => FlutterBluePlus.isSupported;

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
    _lastError = null;
    final found = <String, DiscoveredCane>{};

    // 先挂监听再 startScan：扫描结果是通过流推上来的，
    // 顺序反了会漏掉最开始那一批（往往就包含目标设备）
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        if (!_looksLikeCane(result)) {
          continue;
        }
        final address = result.device.remoteId.str.toUpperCase();
        found[address] = DiscoveredCane(
          bleAddress: address,
          name: _displayNameOf(result),
          rssi: result.rssi,
          // 本地扫描无法知道云端档案，一律标 false，
          // 由状态层再向后端查一次（真机路径下用 /mock/ble/scan 的能力只在演示模式有）
          registered: false,
        );
      }
    });

    try {
      await FlutterBluePlus.startScan(
        // 刻意**不按服务过滤**：ESP32 的广播包里不一定带 NUS UUID
        // （取决于固件把哪些字段放进 advertising data），
        // 按服务过滤会直接把设备滤没。改为本地按名字/服务双条件识别
        withServices: const [],
        // Web 端必须显式声明 optionalServices，否则拿到句柄后
        // 也读不到 NUS 服务（浏览器会拒绝 getPrimaryService）
        webOptionalServices: [Guid(BleProtocol.serviceUuid)],
        // Android 12+ 用 BLUETOOTH_SCAN(neverForLocation) 就够，
        // 置真会让插件去申请 ACCESS_FINE_LOCATION（manifest 里 maxSdkVersion=30）
        // → 在 Android 12+ 上必然被拒 → 扫描直接失败
        androidUsesFineLocation: false,
        // 我们不需要位置数据（neverForLocation），因此也不该因为
        // 「系统定位开关关着」而拒绝扫描
        androidCheckLocationServices: false,
        timeout: timeout,
      );
    } on Exception catch (e) {
      _lastError = _humanize(e);
    } finally {
      await _scanSub?.cancel();
      _scanSub = null;
      try {
        await FlutterBluePlus.stopScan();
      } on Exception {
        // 已经停了，忽略
      }
    }

    final list = found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    return list;
  }

  @override
  Future<bool> connect(String bleAddress) async {
    _lastError = null;
    _emitLink(CaneLinkState.connecting);
    try {
      // 连接前必须停扫描：Android 上扫描与 GATT 连接共用射频调度，
      // 边扫边连会让连接超时或极慢（实测可达数秒）
      try {
        await FlutterBluePlus.stopScan();
      } on Exception {
        // 没在扫，忽略
      }

      final device = BluetoothDevice.fromId(bleAddress);
      _device = device;

      await device.connect(
        // flutter_blue_plus 2.x 强制要求显式声明用途。
        // 本项目是高校竞赛作品，属于 License.nonprofit（教育机构/非营利）
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
      );

      _listenConnectionState(device);

      final services = await device.discoverServices();
      final service = _findService(services);
      if (service == null) {
        throw _ServiceMissingException('手杖未提供 NUS 服务（${BleProtocol.serviceUuid}）');
      }
      final tx = _findCharacteristic(service, BleProtocol.txUuid);
      final rx = _findCharacteristic(service, BleProtocol.rxUuid);
      if (tx == null || rx == null) {
        throw _ServiceMissingException('NUS 服务缺少 TX(6E400003) 或 RX(6E400002) 特征');
      }

      _tx = tx;
      _rx = rx;
      _address = bleAddress;
      _muted = false;

      // 先挂 onValueReceived 再订阅：反过来会丢掉订阅成功后
      // 立刻到达的头几帧（手杖 500ms 一帧，很容易撞上）
      _valueSub = tx.onValueReceived.listen(_onBytes);

      final notified = await tx.setNotifyValue(true);
      if (!notified) {
        throw _ServiceMissingException('订阅 TX 通知失败（手杖未启用 Notify？）');
      }

      await _refreshRssi(device);
      _emitLink(CaneLinkState.connected);
      return true;
    } on Exception catch (e) {
      _lastError = _humanize(e);
      await _cleanupLink(keepError: true);
      _emitLink(CaneLinkState.disconnected);
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    await _cleanupLink();
    _emitLink(CaneLinkState.disconnected);
  }

  @override
  Future<bool> sendCommand(String command) async {
    final tx = _tx;
    final rx = _rx;
    final device = _device;
    // 两个特征都要在位才算真正就绪：只有 RX 说明 TX 那步 Notify 订阅没走完，
    // 这时候写命令是"盲发" —— 手杖会执行，但手机收不到它任何回读，
    // 出了问题现场没法判断到底是没发到还是发错了
    if (tx == null || rx == null || device == null || !device.isConnected) {
      _lastError = '手杖未连接，无法下发命令';
      return false;
    }
    try {
      // withoutResponse: false —— 用「有响应的写」而不是「无响应写」。
      // 目的就是让这一行能抛出真实的失败：无响应写总是"成功"返回，
      // 而后端的回执是状态的唯一提交点，不能建立在乐观假设上
      await rx.write(utf8.encode(command),
          withoutResponse: false, timeout: 5);
      if (command == BleProtocol.cmdToggleMute) {
        // 本地跟踪只是给等待回执期间的界面用；权威值仍以后端返回为准
        _muted = !_muted;
      }
      return true;
    } on Exception catch (e) {
      _lastError = _humanize(e);
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    await _cleanupLink();
    await _telemetryCtrl.close();
    await _linkCtrl.close();
  }

  // ------------------------------------------------------------------

  void _listenConnectionState(BluetoothDevice device) {
    _connSub?.cancel();
    _connSub = device.connectionState.listen((next) {
      if (next == BluetoothConnectionState.disconnected) {
        // 手杖关机 / 走出范围 / 被系统回收，都会走到这里。
        // 必须立刻上报：断连是"立刻发生"的事件，靠遥测超时推断
        // 会让过期的 DANGER 在屏幕上多停留好几秒
        unawaited(_cleanupLink());
        _emitLink(CaneLinkState.disconnected);
      }
    });
  }

  void _onBytes(List<int> bytes) {
    if (bytes.isEmpty) {
      return;
    }
    // allowMalformed: 定长缓冲的残帧可能切断 UTF-8 序列，
    // 解码失败不能把整个监听流带崩
    final text = utf8.decode(bytes, allowMalformed: true);
    // 一帧通告理论上就是一行；但真机也可能把两帧粘在一起。
    // 逐行解析，坏行丢弃，好行照收
    for (final line in text.split('\n')) {
      final frame = CaneTelemetry.tryParse(line);
      if (frame != null && !_telemetryCtrl.isClosed) {
        _telemetryCtrl.add(frame);
      }
    }
  }

  Future<void> _refreshRssi(BluetoothDevice device) async {
    try {
      _rssi = await device.readRssi();
    } on Exception {
      // RSSI 读不到不影响链路可用性，只是界面上少一个数字
      _rssi = null;
    }
  }

  Future<void> _cleanupLink({bool keepError = false}) async {
    await _valueSub?.cancel();
    _valueSub = null;
    await _connSub?.cancel();
    _connSub = null;

    final device = _device;
    _device = null;
    _tx = null;
    _rx = null;
    _address = null;
    _rssi = null;
    _muted = false;
    if (!keepError) {
      _lastError = null;
    }

    if (device != null) {
      try {
        await device.disconnect();
      } on Exception {
        // 已经断了，忽略
      }
    }
  }

  static bool _looksLikeCane(ScanResult result) {
    final advName = result.advertisementData.advName;
    if (advName == BleProtocol.deviceName) {
      return true;
    }
    if (result.device.platformName == BleProtocol.deviceName) {
      return true;
    }
    // 名字可能为空（部分机型/部分固件不把 name 放进广播包），
    // 此时靠"广播了 NUS 服务"这个更强的证据识别
    for (final uuid in result.advertisementData.serviceUuids) {
      if (uuid.toString().toUpperCase() == BleProtocol.serviceUuid) {
        return true;
      }
    }
    return false;
  }

  static String _displayNameOf(ScanResult result) {
    if (result.advertisementData.advName.isNotEmpty) {
      return result.advertisementData.advName;
    }
    if (result.device.platformName.isNotEmpty) {
      return result.device.platformName;
    }
    return BleProtocol.deviceName;
  }

  static BluetoothService? _findService(List<BluetoothService> services) {
    for (final service in services) {
      if (service.serviceUuid.toString().toUpperCase() == BleProtocol.serviceUuid) {
        return service;
      }
    }
    return null;
  }

  static BluetoothCharacteristic? _findCharacteristic(
      BluetoothService service, String uuid) {
    for (final characteristic in service.characteristics) {
      if (characteristic.characteristicUuid.toString().toUpperCase() == uuid) {
        return characteristic;
      }
    }
    return null;
  }

  /// 把插件的异常码翻译成能照着排查的一句话。
  ///
  /// 133 是最常见的 GATT 通用错误（Android 上等价于"操作失败"），
  /// 但它的实际成因大多数时候是**上一次连接没断干净**，
  /// 所以提示语直接给出"关掉手杖电源再开"这个动作。
  String _humanize(Object error) {
    if (error is _ServiceMissingException) {
      return error.message;
    }
    final text = error.toString();
    if (text.contains('133')) {
      return 'GATT 连接失败（错误码 133）。通常是残留连接未释放：'
          '请关掉手杖电源重新上电后重试';
    }
    if (text.contains('permission') || text.contains('Permission')) {
      return '缺少蓝牙权限。请在系统设置里允许本应用使用"附近的设备"';
    }
    if (text.contains('turnedOff') || text.contains('off')) {
      return '手机蓝牙未开启，请先打开蓝牙';
    }
    if (text.contains('timeout') || text.contains('Timeout')) {
      return '连接超时。请确认手杖已上电且距离手机 3 米以内';
    }
    return text;
  }

  void _emitLink(CaneLinkState next) {
    _state = next;
    if (!_linkCtrl.isClosed) {
      _linkCtrl.add(next);
    }
  }
}

/// 服务/特征缺失或订阅失败的专用异常，便于在 [_humanize] 里原样透出中文提示。
class _ServiceMissingException implements Exception {
  _ServiceMissingException(this.message);

  final String message;

  @override
  String toString() => message;
}
