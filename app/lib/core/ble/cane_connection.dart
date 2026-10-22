import 'ble_protocol.dart';

/// 扫描到的一台手杖。
///
/// 字段刻意与后端 `MockBleController#scan` 的返回结构对齐（name / bleAddress /
/// rssi / bound / deviceId / deviceSn），这样「真机扫描」与「演示扫描」
/// 在界面上走同一套渲染逻辑，不会出现两套列表长得不一样的情况。
class DiscoveredCane {
  const DiscoveredCane({
    required this.bleAddress,
    required this.name,
    required this.rssi,
    this.deviceId,
    this.deviceSn,
    this.bound = false,
    this.registered = false,
  });

  /// Android 是硬件 MAC；iOS 是按「手机 + App」随机生成的 UUID，换机就变。
  final String bleAddress;
  final String name;
  final int rssi;

  /// 后端设备主键；未登记到云端的广播（`registered=false`）为 null。
  final int? deviceId;
  final String? deviceSn;

  /// 是否已绑定到某个被监护人。
  final bool bound;

  /// 是否已在家属账号下登记过这台手杖（后端有对应设备档案）。
  final bool registered;

  factory DiscoveredCane.fromJson(Map<String, dynamic> json) {
    return DiscoveredCane(
      bleAddress: (json['bleAddress'] as String? ?? '').toUpperCase(),
      name: json['name'] as String? ?? BleProtocol.deviceName,
      rssi: (json['rssi'] as num?)?.toInt() ?? -70,
      deviceId: (json['deviceId'] as num?)?.toInt(),
      deviceSn: json['deviceSn'] as String?,
      bound: json['bound'] as bool? ?? false,
      registered: json['registered'] as bool? ?? true,
    );
  }

  /// 信号档位 1-4，与后端 `signalLevelOf(rssi)` 的边界保持一致，
  /// 避免同一台手杖在两处显示不同档位。
  int get signalLevel {
    if (rssi >= -60) {
      return 4;
    }
    if (rssi >= -75) {
      return 3;
    }
    if (rssi >= -90) {
      return 2;
    }
    return 1;
  }
}

/// BLE 链路状态。
enum CaneLinkState {
  /// 未连接（初始态，也包含主动断开后）。
  idle,

  /// 正在扫描。
  scanning,

  /// 正在建立连接 / 发现服务 / 订阅通知。
  connecting,

  /// 已连接且通知已订阅 —— 此时才有遥测数据。
  connected,

  /// 连接被断开（手杖关机、走远、被系统回收）。
  disconnected,
}

/// 手杖连接能力的抽象。
///
/// 抽出接口是为了让「真机」与「模拟」在 UI 与状态层完全同构：
/// 上层只认 [CaneLinkState]、[telemetry]、[sendCommand]，
/// 换成模拟实现后整套交互（含命令回执）依然成立，
/// 因此答辩现场即使没有硬件也能演示完整链路。
abstract class CaneConnection {
  /// 遥测帧流。必须是 broadcast —— 界面与状态层会同时消费。
  Stream<CaneTelemetry> get telemetry;

  /// 链路状态变化流。
  Stream<CaneLinkState> get linkStates;

  CaneLinkState get state;

  /// 最近一次失败原因，供界面直白告诉用户「为什么连不上」。
  /// 蓝牙的失败原因（权限被拒 / 适配器关闭 / 服务缺失）用异常码表达，
  /// 不翻译成人话的话，用户只会看到「连接失败」四个字。
  String? get lastError;

  /// 手杖侧当前是否为静音模式（本地已知的最近状态）。
  ///
  /// 注意：**这不是权威值**。权威值在后端 `device.muteMode`，
  /// 界面应优先显示后端状态；这里仅在等待回执期间用于乐观显示。
  bool get muted;

  /// 链路 RSSI（dBm），未连接时为 null。
  int? get rssi;

  /// 当前连接的手杖地址。
  String? get connectedAddress;

  /// 扫描附近的手杖（按广播名 StarPath / NUS 服务过滤）。
  Future<List<DiscoveredCane>> scan({Duration timeout});

  /// 连接并订阅 TX 通知。返回是否成功；失败原因见 [lastError]。
  Future<bool> connect(String bleAddress);

  /// 主动断开。
  Future<void> disconnect();

  /// 向 RX 特征写入一条命令。返回是否**确实写入成功**。
  ///
  /// 这个返回值就是后端 `/command/ack` 里 success 的来源 ——
  /// 它是设备状态的唯一提交点，绝不能「假装成功」。
  Future<bool> sendCommand(String command);

  Future<void> dispose();
}
