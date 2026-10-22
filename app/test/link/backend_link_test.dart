/// S5 端到端联调测试。
///
/// 与 `models_test.dart` 的区别：这里**不 mock 任何东西**，直接用 App 真实的
/// [ApiClient] / [GuardianRepository] / [GuardianWsClient] 去连真后端，
/// 验证的是「两端契约」——接口路径、字段名、鉴权头、STOMP 主题名是否真的对得上。
/// 单元测试过了但联调挂掉，几乎都是这种契约错位。
///
/// 默认跳过（`flutter test` 不应该依赖后端在跑）。显式开启：
/// ```
/// flutter test test/link/backend_link_test.dart \
///   --dart-define=BACKEND_E2E=true \
///   --dart-define=API_BASE_URL=http://127.0.0.1:8001
/// ```
/// 跌倒 30 秒自动升级涉及真实等待，额外加 `--dart-define=BACKEND_E2E_SLOW=true` 开启。
///
/// 开关走 `--dart-define` 而不是环境变量：与 [AppConfig] 保持同一种配置方式，
/// 避免「同一份代码在命令行和 IDE 里读到不同配置」这类只有换机器才暴露的坑。
library;

import 'dart:async';
import 'dart:io';

import 'package:cane_guardian/core/network/api_client.dart';
import 'package:cane_guardian/core/network/api_response.dart';
import 'package:cane_guardian/core/storage/token_store.dart';
import 'package:cane_guardian/core/ws/ws_client.dart';
import 'package:cane_guardian/data/guardian_repository.dart';
import 'package:cane_guardian/models/alert.dart';
import 'package:cane_guardian/models/device_info.dart';
import 'package:cane_guardian/models/user_info.dart';
import 'package:cane_guardian/models/ward.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 演示账号（ward 1 的主监护人，由后端 DemoAccountBootstrap 确保存在）：
/// 必须是 ward 1 的合法监护人，否则接口会正确返回 103001（无监护权限），
/// 那是权限拦截生效而不是联调失败。
const _phone = '13800138000';
const _sn = 'BC-2024-DEMO01';
const _wardId = 1;

bool get _enabled => const bool.fromEnvironment('BACKEND_E2E');
bool get _slowEnabled => const bool.fromEnvironment('BACKEND_E2E_SLOW');

/// 当前用例轮次里由后端随机生成、经 Mock 响应回显的验证码。
/// 验证码不再固定，所有登录/注册都必须用「本次发送返回的那个码」。
late String _sentCode;

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
  String reason = '',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待超时（${timeout.inSeconds}s）$reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  if (!_enabled) {
    test('S5 后端联调', () {},
        skip: '未开启，需 --dart-define=BACKEND_E2E=true 且后端在 8001 运行');
    return;
  }

  late TokenStore store;
  late ApiClient client;
  late GuardianRepository repo;

  setUpAll(() async {
    // 关键：flutter_test 默认把 HttpClient 换成「一律返回 400」的假实现，
    // 目的是防止单元测试误打真实网络。联调必须显式关掉这个拦截。
    HttpOverrides.global = null;

    SharedPreferences.setMockInitialValues({});
    store = await TokenStore.create();
    client = ApiClient(store: store);
    repo = GuardianRepository(client);
  });

  setUp(() {
    // 每个用例前重申一次，避免 binding 在某些路径下重新装回假实现
    HttpOverrides.global = null;
  });

  group('S5 端到端联调（真实后端）', () {
    test('1. 发送验证码：Mock 短信随机生成并随响应回显', () async {
      await repo.mockResetSms(_phone);
      final result = await repo.sendSmsCode(_phone);
      expect(result.mock, isTrue, reason: '开发期应走 Mock 短信通道');
      // 验证码由后端随机生成（不再固定），Mock 模式随响应回显便于演示与联调
      expect(result.mockCode, isNotNull, reason: 'Mock 模式下响应应回显验证码');
      expect(result.mockCode, matches(RegExp(r'^\d{6}$')),
          reason: '验证码应为 6 位随机数字');
      expect(result.expireSeconds, greaterThan(0));
      _sentCode = result.mockCode!;
    });

    test('2. 登录：拿到双令牌并落盘会话', () async {
      final login = await repo.login(phone: _phone, smsCode: _sentCode);
      expect(login.accessToken, isNotEmpty);
      expect(login.refreshToken, isNotEmpty);
      expect(login.expiresIn, greaterThan(0), reason: '后端应返回 accessToken 有效期');
      expect(login.userInfo.phone, _phone);

      await store.saveSession(
        accessToken: login.accessToken,
        refreshToken: login.refreshToken,
        userId: login.userInfo.id,
        phone: login.userInfo.phone,
        nickname: login.userInfo.nickname,
      );
      expect(store.isLoggedIn, isTrue);
      // 后续所有请求靠这个拦截器注入 Authorization
      expect(store.accessToken, isNotEmpty);
    });

    test('3. 被监护人列表：包含 ward 1 且带设备与待处理角标', () async {
      final wards = await repo.listWards();
      expect(wards, isNotEmpty, reason: '演示账号应至少有一个被监护人');

      final ward = wards.firstWhere((w) => w.id == _wardId);
      expect(ward.name, isNotEmpty);
      expect(ward.isPrimaryGuardian, isTrue, reason: '演示账号是主监护人');
      expect(ward.device, isNotNull, reason: 'ward 1 应已绑定演示设备');
      expect(ward.device!.deviceSn, _sn);
    });

    test('4. 被监护人详情：含病史字段且不含敏感越权数据', () async {
      final detail = await repo.getWard(_wardId);
      expect(detail.id, _wardId);
      expect(detail.name, isNotEmpty);
      expect(detail.primaryUserId, isNotNull);
    });

    test('5. 设备状态：复位后在线且电量恢复到初始值', () async {
      await repo.mockResetDevice(_sn);

      final detail = await repo.getWard(_wardId);
      final deviceId = detail.device!.id;

      final status = await repo.deviceStatus(deviceId);
      expect(status.deviceSn, _sn);
      expect(status.online, isTrue);
      expect(status.battery, 85, reason: '复位后电量回到 85%');
      expect(status.batteryLevel, BatteryLevel.normal);
    });

    test('6. 位置链路：上报后 REST 能读到最新位置', () async {
      final lng = 113.7861;
      final lat = 34.7431;
      await client.postRaw(
        '/api/v1/mock/devices/$_sn/location',
        query: {'lng': lng, 'lat': lat, 'accuracy': 8.5, 'speed': 1.1},
      );

      final latest = await repo.latestLocation(_wardId);
      expect(latest, isNotNull, reason: '上报后应能从 Redis 读回热数据');
      // 经度/纬度最容易写反（MySQL SRID 4326 是「纬度在前」），
      // 这里用「经度 > 100 而纬度 < 40」把写反的情况钉死
      expect(latest!.lng, closeTo(lng, 1e-4));
      expect(latest.lat, closeTo(lat, 1e-4));
      expect(latest.isStale, isFalse, reason: '刚上报的位置不应判定为陈旧');
      expect(latest.displayAddress, isNotEmpty);
    });

    test('7. 告警列表：分页结构与字段可被前端模型完整解析', () async {
      final page = await repo.queryAlerts(wardId: _wardId, page: 1, size: 5);
      expect(page.records.length, lessThanOrEqualTo(5));

      if (page.records.isNotEmpty) {
        final first = page.records.first;
        expect(first.id, greaterThan(0));
        expect(first.wardId, _wardId);
        expect(first.alertType, isNotEmpty);
        expect(first.severity, inInclusiveRange(1, 3));
        // 状态文案要么由后端给出，要么由前端兜底，不能是空串
        expect(first.statusLabel, isNotEmpty);
        expect(first.severityLabel, isNotEmpty);
      }
    });

    test('8. WebSocket：连接成功并订阅到 ward 的三个主题', () async {
      final ws = GuardianWsClient(store);
      final locations = <LatestLocation>[];
      final alerts = <AlertRecord>[];

      final subs = <StreamSubscription<dynamic>>[
        ws.locations.listen(locations.add),
        ws.alerts.listen(alerts.add),
        ws.statuses.listen((_) {}),
      ];
      addTearDown(() async {
        for (final s in subs) {
          await s.cancel();
        }
        ws.dispose();
      });

      ws.connect(_wardId);
      await _waitFor(
        () => ws.status == WsStatus.connected,
        reason: 'STOMP 未在 15 秒内连上，检查 /ws 放行与 CONNECT 帧鉴权',
      );
      expect(ws.status, WsStatus.connected);

      // 位置推送：订阅名写错的话这里收不到
      await client.postRaw(
        '/api/v1/mock/devices/$_sn/location',
        query: {'lng': 113.7872, 'lat': 34.7442, 'accuracy': 7.0, 'speed': 1.0},
      );
      await _waitFor(
        () => locations.isNotEmpty,
        timeout: const Duration(seconds: 12),
        reason: '/topic/ward/$_wardId/location 未收到推送',
      );
      expect(locations.last.lng, closeTo(113.7872, 1e-4));

      // 设备状态推送
      await repo.mockBattery(_sn, 15);
      await _waitFor(
        () => locations.isNotEmpty,
        timeout: const Duration(seconds: 5),
      );

      // 告警推送
      await repo.mockSos(_sn);
      await _waitFor(
        () => alerts.any((a) => a.alertType == 'SOS'),
        timeout: const Duration(seconds: 12),
        reason: '/topic/ward/$_wardId/alert 未收到推送',
      );
      final pushed = alerts.lastWhere((a) => a.alertType == 'SOS');
      expect(pushed.severity, AlertRecord.severityCritical);
      expect(pushed.isPending, isTrue);
      expect(
        pushed.requiresFullScreen,
        isTrue,
        reason: 'SOS 必须触发全屏强提醒，这是家属端最核心的一条通路',
      );
    });

    test('9. SOS 处置闭环：处理接口把状态推到已处理', () async {
      await repo.mockSos(_sn);

      final page = await repo.queryAlerts(wardId: _wardId, page: 1, size: 10);
      final target = page.records.firstWhere(
        (a) => a.alertType == 'SOS' && a.isPending,
        orElse: () => throw StateError('未找到待处理的 SOS 告警'),
      );

      final handled = await repo.handleAlert(
        alertId: target.id,
        result: 'RESOLVED',
        note: 'S5 联调自动处理',
      );
      expect(handled.status, AlertRecord.statusResolved);
      expect(handled.handledAt, isNotNull);

      // 详情接口应回读到同样的状态
      final reread = await repo.alertDetail(target.id);
      expect(reread.status, AlertRecord.statusResolved);
    });

    test('10. 倒计时确认闭环：取消疑似跌倒后置为误报且不可重复取消', () async {
      final fall = await repo.mockFall(_sn);
      expect(fall.alertType, 'FALL_DETECTED');
      expect(
        fall.isAwaitingConfirm,
        isTrue,
        reason: '刚产生的跌倒告警应处于 30 秒待确认窗口',
      );
      // 30 秒窗口内还不是紧急级，避免误报打断家属
      expect(fall.severity, AlertRecord.severityWarning);

      await repo.mockCancelFall(_sn, fall.id);

      final cancelled = await repo.alertDetail(fall.id);
      expect(cancelled.status, AlertRecord.statusFalseAlarm);
      expect(cancelled.isAwaitingConfirm, isFalse);

      // 重复取消应被幂等地拒绝（业务码 109003），而不是抛未知异常
      await expectLater(
        repo.mockCancelFall(_sn, fall.id),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 109003),
        ),
      );
    });

    test('11. 令牌刷新：refreshToken 能换到新的双令牌', () async {
      final response = await client.postRaw(
        '/api/v1/auth/refresh',
        body: {'refreshToken': store.refreshToken},
      );
      final data = response as Map<String, dynamic>;
      final newAccess = data['accessToken'] as String?;
      final newRefresh = data['refreshToken'] as String?;

      expect(newAccess, isNotNull);
      expect(newRefresh, isNotNull);
      expect(newRefresh, isNot(store.refreshToken), reason: '刷新令牌应轮换');

      await store.updateTokens(accessToken: newAccess!, refreshToken: newRefresh!);
      // 换完之后原接口仍然可用，说明新令牌有效
      final wards = await repo.listWards();
      expect(wards, isNotEmpty);
    });

    test('12. 越权拦截：非监护人手机号取不到 ward 1', () async {
      // 登录不再自动注册（返回 101011），必须走显式注册建一个
      // 没有任何监护关系的新用户。号码可能在往轮联调里已注册过，
      // 此时 101010 改用密码登录拿同一账号的令牌，不影响断言目标
      const stranger = '13900139000';
      const strangerPwd = 'stranger123';
      await repo.mockResetSms(stranger);
      final sms = await repo.sendSmsCode(stranger);
      late final LoginResult login;
      try {
        login = await repo.register(
          phone: stranger,
          password: strangerPwd,
          smsCode: sms.mockCode!,
        );
      } on ApiException catch (e) {
        if (e.code != 101010) rethrow;
        login = await repo.login(phone: stranger, password: strangerPwd);
      }

      // 换到这个新用户的令牌去读 ward 1
      final strangerClient = ApiClient(store: store);
      final strangerRepo = GuardianRepository(strangerClient);
      final savedAccess = store.accessToken;
      final savedRefresh = store.refreshToken;
      try {
        await store.updateTokens(
          accessToken: login.accessToken,
          refreshToken: login.refreshToken,
        );
        await expectLater(
          strangerRepo.getWard(_wardId),
          throwsA(
            isA<ApiException>().having((e) => e.code, 'code', 103001),
          ),
        );
      } finally {
        await store.updateTokens(accessToken: savedAccess!, refreshToken: savedRefresh!);
      }
    });

    test(
      '13. 跌倒 30 秒未确认自动升级为紧急',
      () async {
        final fall = await repo.mockFall(_sn);
        expect(fall.severity, AlertRecord.severityWarning);

        // 后端 FallConfirmScanTask 每 5 秒扫一次，超时阈值 30 秒。
        // 轮询而不是死等固定时长：升级一发生就立刻断言，跑起来更快也更稳。
        AlertRecord? escalated;
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (DateTime.now().isBefore(deadline)) {
          final current = await repo.alertDetail(fall.id);
          if (current.severity == AlertRecord.severityCritical) {
            escalated = current;
            break;
          }
          await Future<void>.delayed(const Duration(seconds: 3));
        }

        expect(
          escalated,
          isNotNull,
          reason: '超过 30 秒未确认应自动升级为紧急告警',
        );
        expect(escalated!.pendingConfirm, isNot(1), reason: '升级后应退出待确认态');
        expect(
          escalated.requiresFullScreen,
          isTrue,
          reason: '升级后必须能触发全屏强提醒',
        );

        await repo.handleAlert(alertId: fall.id, result: 'RESOLVED', note: 'S5 联调收尾');
      },
      skip: _slowEnabled ? false : '需 --dart-define=BACKEND_E2E_SLOW=true（涉及真实等待 40 秒）',
    );
  });
}
