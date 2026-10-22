/// BLE 协议层（《BLE 对接规格 v1》第 2、3、4 节）。
///
/// 这一层刻意**不依赖任何蓝牙插件**：只放常量与报文解析。
/// 好处是它可以被纯 Dart 单元测试覆盖 —— 报文是外部输入，
/// 真实固件会出现大小写、空格、缺字段、定长缓冲补 `\0` 等五花八门的情况，
/// 而现场没有调试器可用。把所有畸形输入的预期行为钉在测试里，
/// 是这一层唯一值得做的事。
library;

/// 前方障碍状态。
///
/// 取值与固件报文首字段、后端 `ObstacleStatus` 枚举严格一致（CLEAR/NEAR/DANGER）。
enum ObstacleStatus {
  clear('畅通'),
  near('有障碍'),
  danger('危险');

  const ObstacleStatus(this.label);

  /// 中文标签，直接用于界面与提示语。
  final String label;

  /// 越严重值越大。界面排序、是否需要强提醒都按它判断。
  int get severity => index;

  /// 按距离推导状态。
  ///
  /// 阈值与后端配置 `blindcane.device.obstacle-near-cm / obstacle-danger-cm`
  /// 必须保持一致 —— 两边判定不同的话，App 显示的档位会与云端入库的档位打架。
  /// 20cm 归 NEAR（规格：`20cm ≤ 距离 < 100cm` 为有障碍），19cm 才进 DANGER。
  static ObstacleStatus fromDistance(int distanceCm) {
    if (distanceCm < BleProtocol.dangerCm) {
      return ObstacleStatus.danger;
    }
    if (distanceCm < BleProtocol.nearCm) {
      return ObstacleStatus.near;
    }
    return ObstacleStatus.clear;
  }

  /// 解析后端/固件给的状态串（大小写不敏感）。
  ///
  /// 返回 null 让调用方明确处理「未知」：界面显示"未知"比猜一个档位安全，
  /// 因为猜错会把"畅通"显示成"危险"或反之，两个方向都会误导人。
  static ObstacleStatus? tryParse(String raw) {
    final normalized = raw.trim().toUpperCase();
    if (normalized.isEmpty) {
      return null;
    }
    for (final status in ObstacleStatus.values) {
      if (status.name.toUpperCase() == normalized) {
        return status;
      }
    }
    return null;
  }
}

/// 规格常量。UUID 必须与手杖固件（Nordic UART Service）逐字节一致。
class BleProtocol {
  const BleProtocol._();

  /// NUS 服务。
  static const String serviceUuid = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';

  /// 手杖 → 手机（Notify + Read），遥测报文走这里。
  static const String txUuid = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';

  /// 手机 → 手杖（Write），命令走这里。
  static const String rxUuid = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';

  /// 标准 CCCD。flutter_blue_plus 的 setNotifyValue(true) 会自动写这个描述符，
  /// 这里保留常量只是为了文档完整性与排障时对照抓包。
  static const String cccdUuid = '00002902-0000-1000-8000-00805F9B34FB';

  /// 广播名。扫描时按它过滤。
  static const String deviceName = 'StarPath';

  /// 切换工作/静音模式。固件侧对 mode 取反。
  static const String cmdToggleMute = 'M';

  /// 障碍阈值：≥100cm 畅通 / 20~100cm 有障碍 / <20cm 危险。
  static const int nearCm = 100;
  static const int dangerCm = 20;

  /// 距离量程上限。HC-SR04 标称 2~400cm，这里放到 2000 只是防御性上限：
  /// 挡住明显脏数据，又不至于误杀换型后量程更大的模块。
  static const int maxDistanceCm = 2000;

  /// 电量合理范围。当前原型硬件无电量检测，该字段属预留扩展。
  static const int minBattery = 0;
  static const int maxBattery = 100;
}

/// 一帧遥测。
class CaneTelemetry {
  const CaneTelemetry({
    required this.status,
    required this.distanceCm,
    required this.raw,
    this.battery,
  });

  /// 障碍状态。**必定有值** —— 解析不出状态又没有距离的帧会被丢弃。
  final ObstacleStatus status;

  /// 距离（cm）。固件可能省略该字段，此时为 null。
  final int? distanceCm;

  /// 电量（%）。规格里属预留扩展，当前原型硬件不发送，故通常为 null。
  final int? battery;

  /// 原始报文字符串，排障时显示在界面上，便于现场比对固件输出。
  final String raw;

  /// 解析一行 NUS 文本报文。格式：`<状态>,<距离cm>[,<电量>]`
  ///
  /// 返回 null 表示这一行完全不可用（空行、定长缓冲的残留、非遥测文本）。
  /// 没有任何异常路径 —— 固件行为不可预期，解析器绝不能把整个监听流带崩。
  static CaneTelemetry? tryParse(String raw) {
    // 定长缓冲常把剩余字节补成 \0，先统一剥掉再判空：
    // 一个只含 \0 的"空帧"必须被当成空，而不是被当作长度为 1 的脏状态串
    final cleaned = raw.replaceAll('\u0000', '').trim();
    if (cleaned.isEmpty) {
      return null;
    }

    final parts = cleaned.split(',');
    final statusToken = parts[0].trim();
    final distanceCm = parts.length > 1 ? _parseDistance(parts[1].trim()) : null;
    final battery = parts.length > 2 ? _parseBattery(parts[2].trim()) : null;

    // 与后端 `DeviceTelemetryServiceImpl` 遵守**同一条**裁决策略：距离优先。
    //
    // 距离是物理量，状态词只是固件对这个物理量的解释。两者打架的原因很多 ——
    // 固件阈值与规格不一致、串口串帧、将来改档位而忘了同步另一端。
    // 如果这里按状态词、后端按距离，同一帧就会出现「手机显示有障碍、
    // 云端入库危险」这种两端不一致，排障时最难查的正是这种。
    //
    // 反过来，固件省略距离字段时（规格允许），只能退回状态词。
    ObstacleStatus? status;
    if (distanceCm != null) {
      status = ObstacleStatus.fromDistance(distanceCm);
    } else {
      status = _parseStatus(statusToken);
    }
    if (status == null) {
      return null;
    }

    return CaneTelemetry(
      status: status,
      distanceCm: distanceCm,
      battery: battery,
      raw: raw,
    );
  }

  static ObstacleStatus? _parseStatus(String token) {
    if (token.isEmpty) {
      return null;
    }
    final normalized = token.toUpperCase();
    for (final status in ObstacleStatus.values) {
      if (status.name.toUpperCase() == normalized) {
        return status;
      }
    }
    return null;
  }

  /// 脏距离按「本帧没带距离」处理，而不是按 0 处理 ——
  /// 当成 0 会立刻显示「危险 0cm」，一个串口毛刺就足以吓到家属。
  static int? _parseDistance(String token) {
    final value = int.tryParse(token);
    if (value == null) {
      return null;
    }
    if (value < 0 || value > BleProtocol.maxDistanceCm) {
      return null;
    }
    return value;
  }

  static int? _parseBattery(String token) {
    final value = int.tryParse(token);
    if (value == null) {
      return null;
    }
    if (value < BleProtocol.minBattery || value > BleProtocol.maxBattery) {
      return null;
    }
    return value;
  }

  @override
  String toString() =>
      'CaneTelemetry(${status.name}, ${distanceCm ?? '-'}cm, raw=$raw)';
}
