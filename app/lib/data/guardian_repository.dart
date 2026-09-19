import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/network/api_response.dart';
import '../models/alert.dart';
import '../models/device_info.dart';
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

  /// 发送验证码。Mock 模式下后端会把验证码直接放在 data 里返回。
  Future<SmsCodeResult> sendSmsCode(String phone) async {
    final data = await _client.postRaw(_p('/auth/sms/send'), body: {'phone': phone});
    final json = (data as Map<String, dynamic>?) ?? const {};
    return SmsCodeResult(
      mock: json['mock'] as bool? ?? false,
      mockCode: json['mockCode'] as String?,
      expireSeconds: (json['expireSeconds'] as num?)?.toInt() ?? 300,
    );
  }

  Future<LoginResult> login({required String phone, required String smsCode}) async {
    final data = await _client.postRaw(
      _p('/auth/login'),
      body: {'phone': phone, 'smsCode': smsCode},
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
    String? medicalNotes,
  }) async {
    final data = await _client.postRaw(_p('/wards'), body: {
      'name': name,
      if (relation != null && relation.isNotEmpty) 'relation': relation,
      'birthYear': ?birthYear,
      if (homeAddress != null && homeAddress.isNotEmpty) 'homeAddress': homeAddress,
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
    String? medicalNotes,
  }) async {
    final data = await _client.putRaw(_p('/wards/$wardId'), body: {
      'name': name,
      if (relation != null && relation.isNotEmpty) 'relation': relation,
      'birthYear': ?birthYear,
      if (homeAddress != null && homeAddress.isNotEmpty) 'homeAddress': homeAddress,
      // 病史允许清空：显式传空串而不是省略字段
      'medicalNotes': medicalNotes ?? '',
    });
    return WardDetail.fromJson(data as Map<String, dynamic>);
  }

  // ---------------- 设备 ----------------

  Future<DeviceInfo> bindDevice({required String deviceSn, required int wardId}) async {
    final data = await _client.postRaw(
      _p('/devices/bind'),
      body: {'deviceSn': deviceSn, 'wardId': wardId},
    );
    return DeviceInfo.fromJson(data as Map<String, dynamic>);
  }

  Future<void> unbindDevice(int deviceId) async {
    await _client.postRaw(_p('/devices/$deviceId/unbind'));
  }

  Future<DeviceInfo> deviceStatus(int deviceId) async {
    final data = await _client.getRaw(_p('/devices/$deviceId/status'));
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
