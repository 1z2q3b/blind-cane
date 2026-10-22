import '../core/ble/cane_connection.dart';
import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/network/api_response.dart';
import '../models/alert.dart';
import '../models/device_info.dart';
import '../models/geofence.dart';
import '../models/user_info.dart';
import '../models/ward.dart';

/// 后端接口的唯一出口。
///
/// 所有接口路径都集中在这里，好处是后端一改路径只需要动一个文件；
/// 反过来如果让每个页面各自拼 URL，很容易出现「有的写了 /api/v1 有的没写」
/// 这种只在真机上才暴露的问题。
class GuardianRepository {
  GuardianRepository(this._client);

  final ApiClient _client;

  String _p(String path) => '${AppConfig.apiPrefix}$path';

  // ---------------- 认证 ----------------

  /// 发送验证码。Mock 模式下后端会把验证码直接放在 data 里返回
  /// （验证码由后端随机生成，一次性消费，5 分钟有效）。
  Future<SmsCodeResult> sendSmsCode(String phone) async {
    final data = await _client.postRaw(_p('/auth/sms/send'), body: {'phone': phone});
    final json = (data as Map<String, dynamic>?) ?? const {};
    return SmsCodeResult(
      mock: json['mock'] as bool? ?? false,
      mockCode: json['mockCode'] as String?,
      expireSeconds: (json['expireSeconds'] as num?)?.toInt() ?? 300,
    );
  }

  /// 注册：手机号 + 密码 + 验证码。成功后直接返回双令牌（无需再登录）。
  Future<LoginResult> register({
    required String phone,
    required String password,
    required String smsCode,
  }) async {
    final data = await _client.postRaw(
      _p('/auth/register'),
      body: {'phone': phone, 'password': password, 'smsCode': smsCode},
    );
    return LoginResult.fromJson(data as Map<String, dynamic>);
  }

  /// 登录：验证码登录（传 [smsCode]）或密码登录（传 [password]），二选一。
  ///
  /// 两者都传或都不传后端返回 101014；调用方按当前页面的登录方式传其一即可。
  Future<LoginResult> login({
    required String phone,
    String? smsCode,
    String? password,
  }) async {
    final data = await _client.postRaw(
      _p('/auth/login'),
      body: {
        'phone': phone,
        'smsCode': ?smsCode,
        'password': ?password,
      },
    );
    return LoginResult.fromJson(data as Map<String, dynamic>);
  }

  Future<void> logout() async {
    final refreshToken = _client.store.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      return;
    }
    // 登出失败（例如令牌已过期）不应该阻塞本地清理，所以吞掉异常：
    // 服务端的黑名单只是加固措施，本地清掉令牌才是用户能感知到的那一步。
    try {
      await _client.postRaw(_p('/auth/logout'), body: {'refreshToken': refreshToken});
    } catch (_) {
      // ignore
    }
  }

  // ---------------- 被监护人 ----------------

  Future<List<Ward>> listWards() async {
    final data = await _client.getRaw(_p('/wards'));
    final list = (data as List<dynamic>?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(Ward.fromJson)
        .toList(growable: false);
  }

  Future<WardDetail> getWard(int wardId) async {
    final data = await _client.getRaw(_p('/wards/$wardId'));
    return WardDetail.fromJson(data as Map<String, dynamic>);
  }

  Future<WardDetail> createWard({
    required String name,
    String? relation,
    int? birthYear,
    String? homeAddress,
    double? homeLng,
    double? homeLat,
    String? contactPhone,
    String? medicalNotes,
  }) async {
    final data = await _client.postRaw(_p('/wards'), body: {
      'name': name,
      if (relation != null && relation.isNotEmpty) 'relation': relation,
      'birthYear': ?birthYear,
      if (homeAddress != null && homeAddress.isNotEmpty) 'homeAddress': homeAddress,
      'homeLng': ?homeLng,
      'homeLat': ?homeLat,
      if (contactPhone != null && contactPhone.isNotEmpty) 'contactPhone': contactPhone,
      if (medicalNotes != null && medicalNotes.isNotEmpty) 'medicalNotes': medicalNotes,
    });
    return WardDetail.fromJson(data as Map<String, dynamic>);
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
    final data = await _client.putRaw(_p('/wards/$wardId'), body: {
      'name': name,
      if (relation != null && relation.isNotEmpty) 'relation': relation,
      'birthYear': ?birthYear,
      if (homeAddress != null && homeAddress.isNotEmpty) 'homeAddress': homeAddress,
      'homeLng': ?homeLng,
      'homeLat': ?homeLat,
      // 号码允许清空：传空串表示"抹掉旧号码"，null（不传）表示不修改
      'contactPhone': ?contactPhone,
      // 病史允许清空：显式传空串而不是省略字段
      'medicalNotes': medicalNotes ?? '',
    });
    return WardDetail.fromJson(data as Map<String, dynamic>);
  }

  /// 删除档案。
  ///
  /// 服务端会连带清理该档案的围栏、位置流水、告警历史与监护关系，
  /// 已绑定的手杖会被解绑（设备本身不删除），所以调用方不需要再补别的请求。
  Future<void> deleteWard(int wardId) async {
    await _client.deleteRaw(_p('/wards/$wardId'));
  }

  // ---------------- 设备 ----------------

  Future<DeviceInfo> bindDevice({
    required String deviceSn,
    required int wardId,
    String? bleAddress,
    String? name,
  }) async {
    final data = await _client.postRaw(_p('/devices/bind'), body: {
      'deviceSn': deviceSn,
      'wardId': wardId,
      // 扫描列表里点中的那一项本来就带着地址，此时顺手提交，
      // 省掉让用户再去设置页手工登记一次
      if (bleAddress != null && bleAddress.isNotEmpty) 'bleAddress': bleAddress,
      if (name != null && name.isNotEmpty) 'name': name,
    });
    return DeviceInfo.fromJson(data as Map<String, dynamic>);
  }

  Future<void> unbindDevice(int deviceId) async {
    await _client.postRaw(_p('/devices/$deviceId/unbind'));
  }

  Future<DeviceInfo> deviceStatus(int deviceId) async {
    final data = await _client.getRaw(_p('/devices/$deviceId/status'));
    return DeviceInfo.fromJson(data as Map<String, dynamic>);
  }

  // ---------------- BLE 接入（手机作为网关） ----------------

  /// 上报一帧障碍遥测。
  ///
  /// 对应固件上行报文 `<状态>,<距离cm>`，由 App 解析后转成结构化 JSON。
  /// `status` 与 `distanceCm` 至少给一个；后端两者都收到时**以距离为准**，
  /// 这样固件状态词写错也不会让云端记错档位。
  Future<TelemetryAck> reportTelemetry({
    required int deviceId,
    required String status,
    int? distanceCm,
    int? battery,
    int? rssi,
  }) async {
    final data = await _client.postRaw(
      _p('/devices/$deviceId/telemetry'),
      body: {
        'status': status,
        // 不传 null 字段：后端对 Integer 收到空串会 400，
        // 而 Jackson 反序列化 null 是允许的，所以只用"省略"表达"没有"
        'distanceCm': ?distanceCm,
        'battery': ?battery,
        'rssi': ?rssi,
        'reportedAtMs': DateTime.now().millisecondsSinceEpoch,
      },
    );
    return TelemetryAck.fromJson(data as Map<String, dynamic>);
  }

  /// 上报蓝牙链路连/断，各调一次。
  ///
  /// 断开必须显式上报：断连是瞬时事件，靠遥测超时推断至少滞后一个节流窗口，
  /// 而在这段滞后期里云端仍持有断开前最后的 `DANGER`，
  /// 家属端会把它当作当前状态显示出来。
  Future<DeviceInfo> reportBleLink({
    required int deviceId,
    required bool connected,
    int? rssi,
  }) async {
    final data = await _client.postRaw(
      _p('/devices/$deviceId/ble-link'),
      body: {
        'connected': connected,
        // 断开时链路已经没了，任何 RSSI 都是无意义的残留值
        if (connected && rssi != null) 'rssi': rssi,
      },
    );
    return DeviceInfo.fromJson(data as Map<String, dynamic>);
  }

  /// 下发命令到手杖。
  ///
  /// **本接口不改变设备状态** —— 后端只广播，要等 [ackCommand] 回执才提交。
  Future<DeviceCommandMessage> issueCommand({
    required int deviceId,
    required String command,
  }) async {
    final data = await _client.postRaw(
      _p('/devices/$deviceId/command'),
      body: {'command': command},
    );
    return DeviceCommandMessage.fromJson(data as Map<String, dynamic>);
  }

  /// 命令执行回执 —— 设备状态的唯一提交点。
  ///
  /// [success] 必须来自「RX 特征是否真的写入成功」的真实结果，
  /// 绝不能乐观置真：一次写失败被当成成功，云端会与手杖永久失步
  /// （界面显示已静音，手杖还在响）。
  Future<DeviceInfo> ackCommand({
    required int deviceId,
    required String command,
    required bool success,
    String? detail,
  }) async {
    final data = await _client.postRaw(
      _p('/devices/$deviceId/command/ack'),
      body: {
        'command': command,
        'success': success,
        if (detail != null && detail.isNotEmpty) 'detail': detail,
      },
    );
    return DeviceInfo.fromJson(data as Map<String, dynamic>);
  }

  /// 登记 / 刷新手杖蓝牙地址。
  ///
  /// 换手机后必须重新登记：iOS 给外设分配的是随每台手机随机生成的 UUID，
  /// 不刷新则自动重连永远匹配不上。冲突返回 104006。
  Future<DeviceInfo> bindBleAddress({
    required int deviceId,
    required String bleAddress,
  }) async {
    final data = await _client.postRaw(
      _p('/devices/$deviceId/ble-address'),
      body: {'bleAddress': bleAddress},
    );
    return DeviceInfo.fromJson(data as Map<String, dynamic>);
  }

  // ---------------- 位置 ----------------

  Future<LatestLocation?> latestLocation(int wardId) async {
    final data = await _client.getRaw(_p('/locations/realtime'), query: {'wardId': wardId});
    if (data == null) {
      return null;
    }
    return LatestLocation.fromJson(data as Map<String, dynamic>);
  }

  /// 历史轨迹（轨迹回放用）。
  ///
  /// 时间按后端约定的 `yyyy-MM-dd HH:mm:ss` 传，不传则后端默认取「今天」。
  /// 后端会自动等距降采样到 [maxPoints] 个点，所以这里不必担心一天上千条点位。
  Future<List<TrackPoint>> fetchTrack({
    required int wardId,
    DateTime? start,
    DateTime? end,
    int maxPoints = 300,
  }) async {
    final data = await _client.getRaw(_p('/locations/history'), query: {
      'wardId': wardId,
      'start': start == null ? null : _fmtDateTime(start),
      'end': end == null ? null : _fmtDateTime(end),
      'maxPoints': maxPoints,
    });
    final list = (data as List<dynamic>?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(TrackPoint.fromJson)
        .toList(growable: false);
  }

  /// 格式化成本地时间字符串。不用 intl 的DateFormat：
  /// 这里只需要固定格式，手写省掉一个 locale 初始化的隐患。
  String _fmtDateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  // ---------------- 电子围栏 ----------------

  Future<List<Geofence>> listGeofences(int wardId) async {
    final data = await _client.getRaw(_p('/geofences'), query: {'wardId': wardId});
    final list = (data as List<dynamic>?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(Geofence.fromJson)
        .toList(growable: false);
  }

  Future<Geofence> createGeofence({
    required int wardId,
    required String name,
    required double centerLng,
    required double centerLat,
    required int radiusM,
    required int fenceType,
    bool enabled = true,
  }) async {
    final data = await _client.postRaw(_p('/geofences'), body: {
      'wardId': wardId,
      'name': name,
      'centerLng': centerLng,
      'centerLat': centerLat,
      'radiusM': radiusM,
      'fenceType': fenceType,
      'enabled': enabled ? 1 : 0,
    });
    return Geofence.fromJson(data as Map<String, dynamic>);
  }

  Future<Geofence> updateGeofence({
    required int id,
    String? name,
    double? centerLng,
    double? centerLat,
    int? radiusM,
    int? fenceType,
    int? enabled,
  }) async {
    final data = await _client.putRaw(_p('/geofences/$id'), body: {
      'name': ?name,
      'centerLng': ?centerLng,
      'centerLat': ?centerLat,
      'radiusM': ?radiusM,
      'fenceType': ?fenceType,
      'enabled': ?enabled,
    });
    return Geofence.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteGeofence(int id) async {
    await _client.deleteRaw(_p('/geofences/$id'));
  }

  Future<Geofence> setGeofenceEnabled(int id, bool enabled) async {
    final data = await _client.putRaw(
      _p('/geofences/$id/enabled'),
      query: {'enabled': enabled ? 1 : 0},
    );
    return Geofence.fromJson(data as Map<String, dynamic>);
  }

  // ---------------- 告警 ----------------

  Future<PageResult<AlertRecord>> queryAlerts({
    int? wardId,
    String? type,
    int? status,
    int page = 1,
    int size = 20,
  }) async {
    final data = await _client.getRaw(_p('/alerts'), query: {
      'wardId': wardId,
      'type': type,
      'status': status,
      'page': page,
      'size': size,
    });
    return PageResult<AlertRecord>.fromJson(
      data as Map<String, dynamic>,
      AlertRecord.fromJson,
    );
  }

  Future<PendingCount> pendingCount() async {
    final data = await _client.getRaw(_p('/alerts/pending-count'));
    return PendingCount.fromJson(data as Map<String, dynamic>);
  }

  Future<AlertRecord> alertDetail(int alertId) async {
    final data = await _client.getRaw(_p('/alerts/$alertId'));
    return AlertRecord.fromJson(data as Map<String, dynamic>);
  }

  /// 处理告警。[result] 取 `RESOLVED`（已处理）或 `FALSE_ALARM`（误报）。
  Future<AlertRecord> handleAlert({
    required int alertId,
    required String result,
    String? note,
  }) async {
    final data = await _client.putRaw(
      _p('/alerts/$alertId/handle'),
      body: {'result': result, if (note != null && note.isNotEmpty) 'note': note},
    );
    return AlertRecord.fromJson(data as Map<String, dynamic>);
  }

  // ---------------- 演示用（后端 simulator.enabled 关闭后不可用） ----------------

  Future<void> mockSos(String deviceSn) async {
    await _client.postRaw(_p('/mock/devices/$deviceSn/sos'));
  }

  Future<AlertRecord> mockFall(String deviceSn) async {
    final data = await _client.postRaw(_p('/mock/devices/$deviceSn/fall'));
    return AlertRecord.fromJson(data as Map<String, dynamic>);
  }

  Future<void> mockCancelFall(String deviceSn, int alertId) async {
    await _client.postRaw(_p('/mock/devices/$deviceSn/fall/$alertId/cancel'));
  }

  Future<void> mockToggleOnline(String deviceSn, {int? ageMinutes}) async {
    await _client.postRaw(
      _p('/mock/devices/$deviceSn/toggle-online'),
      query: {'ageMinutes': ageMinutes},
    );
  }

  Future<void> mockBattery(String deviceSn, int level) async {
    await _client.postRaw(_p('/mock/devices/$deviceSn/battery'), query: {'level': level});
  }

  Future<void> mockResetDevice(String deviceSn) async {
    await _client.postRaw(_p('/mock/devices/$deviceSn/reset'));
  }

  Future<void> mockResetSms(String phone) async {
    await _client.postRaw(_p('/mock/sms/reset'), query: {'phone': phone});
  }

  // ---------------- 演示用：后端扮演「手机网关」的 BLE 接口 ----------------

  /// 模拟 BLE 扫描。返回结构与本地扫描对齐（bleAddress / name / rssi / bound …），
  /// 但多带了后端才知道的 `deviceId` 与 `deviceSn`，界面可以据此区分
  /// 「已登记的自家手杖」与「别人的手杖」。
  Future<List<DiscoveredCane>> mockBleScan() async {
    final data = await _client.getRaw(_p('/mock/ble/scan'));
    final list = (data as List<dynamic>?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(DiscoveredCane.fromJson)
        .toList(growable: false);
  }

  /// 模拟「手机连上手杖」。等价于 App 收到 STATE_CONNECTED 并订阅完 TX 通知。
  Future<DeviceInfo> mockBleConnect(String deviceSn, {int? rssi}) async {
    final data = await _client.postRaw(
      _p('/mock/ble/devices/$deviceSn/connect'),
      query: {'rssi': rssi},
    );
    return DeviceInfo.fromJson(data as Map<String, dynamic>);
  }

  /// 模拟蓝牙断开。验证「断开后 App 把障碍显示切成数据已过期」这条分支。
  Future<DeviceInfo> mockBleDisconnect(String deviceSn) async {
    final data = await _client.postRaw(_p('/mock/ble/devices/$deviceSn/disconnect'));
    return DeviceInfo.fromJson(data as Map<String, dynamic>);
  }

  /// 手动灌一帧遥测，用于观察后端的节流窗口与「距离优先于状态」。
  Future<TelemetryAck> mockBleTelemetry(
    String deviceSn, {
    String? status,
    int? distanceCm,
  }) async {
    final data = await _client.postRaw(
      _p('/mock/ble/devices/$deviceSn/telemetry'),
      query: {'status': status, 'distanceCm': distanceCm},
    );
    return TelemetryAck.fromJson(data as Map<String, dynamic>);
  }

  /// 模拟命令执行回执。[success]=false 可用于验证
  /// 「手机写失败时云端不会错误地认为模式变了」。
  Future<DeviceInfo> mockBleCommandAck(
    String deviceSn, {
    required String command,
    required bool success,
    String? detail,
  }) async {
    final data = await _client.postRaw(
      _p('/mock/ble/devices/$deviceSn/command/ack'),
      query: {'command': command, 'success': success, 'detail': detail},
    );
    return DeviceInfo.fromJson(data as Map<String, dynamic>);
  }
}

/// 发送验证码的结果。
class SmsCodeResult {
  const SmsCodeResult({
    required this.mock,
    this.mockCode,
    required this.expireSeconds,
  });

  final bool mock;

  /// Mock 模式下后端直接回传的验证码，仅用于演示时自动填入。
  final String? mockCode;
  final int expireSeconds;
}
