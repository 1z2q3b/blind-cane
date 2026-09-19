import 'package:cane_guardian/models/alert.dart';
import 'package:cane_guardian/models/device_info.dart';
import 'package:cane_guardian/models/ward.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模型层单元测试。
///
/// 只测「纯函数式」的判定逻辑（电量分级、是否需要全屏提醒、陈旧判定、
/// JSON 兼容性），不碰网络与 UI：这些逻辑一旦错了，界面上表现出来的是
/// 「该弹的告警没弹」或「不该弹的天天弹」，属于最难靠肉眼发现的一类缺陷。
void main() {
  group('LatestLocation', () {
    test('没有逆地理结果时降级显示坐标', () {
      const location = LatestLocation(lng: 113.7853, lat: 34.7423);
      expect(location.displayAddress, '34.74230, 113.78530');
    });

    test('有逆地理结果时优先显示地址', () {
      const location = LatestLocation(
        lng: 113.7853,
        lat: 34.7423,
        address: '郑州市金水区文苑北路 36 号',
      );
      expect(location.displayAddress, '郑州市金水区文苑北路 36 号');
    });

    test('超过 2 分钟未更新判定为陈旧', () {
      final stale = LatestLocation(
        lng: 1,
        lat: 1,
        reportedAt: DateTime.now()
            .subtract(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
      );
      expect(stale.isStale, isTrue);

      final fresh = LatestLocation(
        lng: 1,
        lat: 1,
        reportedAt: DateTime.now().millisecondsSinceEpoch,
      );
      expect(fresh.isStale, isFalse);
    });
  });

  group('DeviceInfo', () {
    DeviceInfo device(int battery) => DeviceInfo(
          id: 1,
          deviceSn: 'BC-2024-DEMO01',
          name: '演示导盲杖',
          battery: battery,
          online: true,
        );

    test('电量分级用于徽章配色', () {
      expect(device(80).batteryLevel, BatteryLevel.normal);
      expect(device(20).batteryLevel, BatteryLevel.low);
      expect(device(10).batteryLevel, BatteryLevel.critical);
    });

    test('离线时给出相对时间文案', () {
      const offline = DeviceInfo(
        id: 1,
        deviceSn: 'SN',
        name: '杖',
        online: false,
        offlineSeconds: 300,
      );
      expect(offline.lastOnlineText, '5 分钟前');
    });
  });

  group('AlertRecord', () {
    AlertRecord alert({
      int severity = 1,
      int status = AlertRecord.statusPending,
      int pendingConfirm = 0,
      String type = 'SOS',
    }) =>
        AlertRecord(
          id: 1,
          wardId: 1,
          alertType: type,
          severity: severity,
          status: status,
          pendingConfirm: pendingConfirm,
        );

    test('只有紧急且未处理才需要全屏强提醒', () {
      expect(alert().requiresFullScreen, isTrue);
      // 中等级别的离线告警不该打断家属
      expect(alert(severity: 2).requiresFullScreen, isFalse);
      // 已处理的紧急告警也不该再弹
      expect(alert(status: AlertRecord.statusResolved).requiresFullScreen, isFalse);
    });

    test('疑似跌倒处于确认窗口内', () {
      expect(
        alert(type: 'FALL_DETECTED', severity: 2, pendingConfirm: 1).isAwaitingConfirm,
        isTrue,
      );
      // 升级后 pendingConfirm 归零，不再显示确认条
      expect(
        alert(type: 'FALL_DETECTED', severity: 1, pendingConfirm: 0).isAwaitingConfirm,
        isFalse,
      );
    });

    test('未知类型不会导致解析失败', () {
      final record = AlertRecord.fromJson(const {
        'id': 9,
        'wardId': 1,
        'alertType': 'SOMETHING_NEW',
        'severity': 3,
        'status': 0,
      });
      expect(record.kind, AlertKind.unknown);
      expect(record.id, 9);
    });
  });

  group('PendingCount', () {
    test('byWard 的 JSON key 是字符串，需要转成 int', () {
      final pending = PendingCount.fromJson(const {
        'total': 3,
        'byWard': {'1': 2, '2': 1},
      });
      expect(pending.total, 3);
      expect(pending.countOf(1), 2);
      expect(pending.countOf(2), 1);
      expect(pending.countOf(99), 0);
    });
  });
}
