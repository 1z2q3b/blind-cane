import 'package:cane_guardian/core/ble/ble_protocol.dart';
import 'package:cane_guardian/core/ble/mock_cane_connection.dart';
import 'package:cane_guardian/models/device_info.dart';
import 'package:flutter_test/flutter_test.dart';

/// BLE 报文解析测试。
///
/// 为什么这些用例值得写：硬件报文是**外部输入**，而且规格里只定义了
/// 一种正常格式，真实固件却可能出现大小写、空格、缺字段、补 \0 等各种情况。
/// 解析器写错的表现是「页面一直显示未知」，而现场没有调试器可用 ——
/// 这里把能想到的畸形输入都钉住。
void main() {
  group('CaneTelemetry.tryParse 正常报文', () {
    test('规格里的三种典型报文', () {
      final clear = CaneTelemetry.tryParse('CLEAR,235')!;
      expect(clear.status, ObstacleStatus.clear);
      expect(clear.distanceCm, 235);
      expect(clear.battery, isNull);

      final near = CaneTelemetry.tryParse('NEAR,80')!;
      expect(near.status, ObstacleStatus.near);
      expect(near.distanceCm, 80);

      final danger = CaneTelemetry.tryParse('DANGER,12')!;
      expect(danger.status, ObstacleStatus.danger);
      expect(danger.distanceCm, 12);
    });

    test('容忍大小写、首尾空白与 \\r\\n', () {
      expect(CaneTelemetry.tryParse('  danger , 12 \r\n')!.status,
          ObstacleStatus.danger);
      expect(CaneTelemetry.tryParse('Near,80')!.status, ObstacleStatus.near);
    });

    test('容忍定长缓冲补的 \\0', () {
      final frame = CaneTelemetry.tryParse('CLEAR,235\u0000\u0000\u0000');
      expect(frame!.status, ObstacleStatus.clear);
      expect(frame.distanceCm, 235);
    });

    test('只给状态、没有距离也能解析', () {
      final frame = CaneTelemetry.tryParse('DANGER')!;
      expect(frame.status, ObstacleStatus.danger);
      expect(frame.distanceCm, isNull);
    });

    test('状态无法识别时用距离兜底', () {
      // 固件把状态词改成了别的（例如中文），只要距离还在，就不该整帧丢弃
      final frame = CaneTelemetry.tryParse('有障碍,45')!;
      expect(frame.status, ObstacleStatus.near);
      expect(frame.distanceCm, 45);
    });

    test('第三字段（电量）为预留扩展，出现时应当被解析', () {
      final frame = CaneTelemetry.tryParse('CLEAR,235,87')!;
      expect(frame.battery, 87);
    });
  });

  group('CaneTelemetry.tryParse 畸形报文', () {
    test('空串与纯空白返回 null', () {
      expect(CaneTelemetry.tryParse(''), isNull);
      expect(CaneTelemetry.tryParse('   '), isNull);
      expect(CaneTelemetry.tryParse('\u0000'), isNull);
    });

    test('完全无法识别的文本返回 null（不抛异常）', () {
      expect(CaneTelemetry.tryParse('AT+OK'), isNull);
      expect(CaneTelemetry.tryParse('失败'), isNull);
    });

    test('距离为脏数据时按「没带距离」处理', () {
      final frame = CaneTelemetry.tryParse('NEAR,abc')!;
      expect(frame.status, ObstacleStatus.near);
      expect(frame.distanceCm, isNull);

      expect(CaneTelemetry.tryParse('NEAR,-5')!.distanceCm, isNull);
      expect(CaneTelemetry.tryParse('NEAR,99999')!.distanceCm, isNull);
    });
  });

  group('障碍阈值与规格一致', () {
    test('100cm 是 CLEAR/NEAR 的分界', () {
      expect(ObstacleStatus.fromDistance(100), ObstacleStatus.clear);
      expect(ObstacleStatus.fromDistance(99), ObstacleStatus.near);
    });

    test('20cm 是 NEAR/DANGER 的分界', () {
      expect(ObstacleStatus.fromDistance(20), ObstacleStatus.near);
      expect(ObstacleStatus.fromDistance(19), ObstacleStatus.danger);
    });
  });

  group('协议常量', () {
    test('UUID 与规格第 2 节一致', () {
      expect(BleProtocol.serviceUuid, '6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
      expect(BleProtocol.txUuid, '6E400003-B5A3-F393-E0A9-E50E24DCCA9E');
      expect(BleProtocol.rxUuid, '6E400002-B5A3-F393-E0A9-E50E24DCCA9E');
      expect(BleProtocol.cccdUuid, '00002902-0000-1000-8000-00805F9B34FB');
      expect(BleProtocol.deviceName, 'StarPath');
      expect(BleProtocol.cmdToggleMute, 'M');
    });

    test('阈值与后端 blindcane.device.obstacle-*-cm 默认值一致', () {
      // 改这里必须同步改 backend/src/main/resources/application.yml，
      // 否则手机档位与云端入库档位会分叉
      expect(BleProtocol.nearCm, 100);
      expect(BleProtocol.dangerCm, 20);
    });
  });

  group('MockCaneConnection 产生的是合法报文', () {
    test('模拟手杖推送的每一帧都能被解析器接受', () async {
      final cane = MockCaneConnection(interval: const Duration(milliseconds: 5));
      addTearDown(cane.dispose);

      final frames = <CaneTelemetry>[];
      final sub = cane.telemetry.listen(frames.add);
      addTearDown(sub.cancel);

      expect(await cane.connect(MockCaneConnection.mockAddress), isTrue);
      // 一个完整循环是 40 帧（30 畅通 + 6 有障碍 + 4 危险），
      // 跑 45 帧足以覆盖三种状态并验证「循环回畅通」
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(frames, isNotEmpty);
      for (final frame in frames) {
        expect(frame.distanceCm, isNotNull);
        expect(frame.distanceCm, greaterThanOrEqualTo(8));
        expect(frame.raw.contains(','), isTrue);
      }
      // 至少出现过两种状态，否则这个模拟器就失去了演示价值
      expect(frames.map((f) => f.status).toSet().length,
          greaterThanOrEqualTo(2));
    });

    test('静音命令 M 会被模拟手杖执行', () async {
      final cane = MockCaneConnection(interval: const Duration(seconds: 1));
      addTearDown(cane.dispose);
      await cane.connect(MockCaneConnection.mockAddress);
      expect(cane.muted, isFalse);
      expect(await cane.sendCommand(BleProtocol.cmdToggleMute), isTrue);
      expect(cane.muted, isTrue);
      expect(await cane.sendCommand('P'), isFalse,
          reason: '预留命令在固件实现前应返回失败，而不是假装成功');
    });
  });

  // ==================================================================
  // 以下为 BLE 接入补测：两端一致性、边界值、以及设备模型的 BLE 语义。
  // ==================================================================

  group('距离优先于状态词（与后端同一条规则）', () {
    // DeviceTelemetryServiceImpl.reportTelemetry 里：
    //   byDistance != null ? byDistance : byHardware
    // 手机端必须裁同一个，否则同一帧会出现「手机显示有障碍、
    // 云端入库危险」，两端不一致是现场最难查的一类问题。
    test('状态词说 NEAR，距离 19cm → 以距离为准判 DANGER', () {
      final frame = CaneTelemetry.tryParse('NEAR,19')!;
      expect(frame.status, ObstacleStatus.danger);
      expect(frame.distanceCm, 19);
    });

    test('状态词说 DANGER，距离 300cm → 以距离为准判 CLEAR', () {
      expect(CaneTelemetry.tryParse('DANGER,300')!.status, ObstacleStatus.clear);
    });

    test('只有距离缺失时才采信状态词', () {
      expect(CaneTelemetry.tryParse('DANGER')!.status, ObstacleStatus.danger);
      expect(CaneTelemetry.tryParse('DANGER,abc')!.status, ObstacleStatus.danger);
    });
  });

  group('距离量程边界', () {
    test('2000 是量程上限本身，2001 越界', () {
      expect(CaneTelemetry.tryParse('CLEAR,2000')!.distanceCm, 2000);
      expect(CaneTelemetry.tryParse('CLEAR,2001')!.distanceCm, isNull);
    });

    test('0cm 是合法读数（贴到障碍物），不能与"没有距离"混同', () {
      final frame = CaneTelemetry.tryParse('CLEAR,0')!;
      expect(frame.distanceCm, 0);
      // 距离既然是 0，档位就该由距离推导为危险
      expect(frame.status, ObstacleStatus.danger);
    });
  });

  group('电量字段越界', () {
    test('越界电量只丢该字段，不影响本帧其他内容', () {
      final frame = CaneTelemetry.tryParse('CLEAR,235,150')!;
      expect(frame.distanceCm, 235);
      expect(frame.battery, isNull);
    });

    test('0 与 100 是合法边界', () {
      expect(CaneTelemetry.tryParse('CLEAR,235,0')!.battery, 0);
      expect(CaneTelemetry.tryParse('CLEAR,235,100')!.battery, 100);
    });
  });

  group('raw 保留原始串', () {
    test('\\0 不会被从 raw 里抹掉 —— 现场要拿它比对固件输出', () {
      const raw = 'DANGER,12\u0000';
      expect(CaneTelemetry.tryParse(raw)!.raw, raw);
    });
  });

  group('ObstacleStatus.severity', () {
    test('单调递增，界面排序与强提醒判断靠它', () {
      expect(
          ObstacleStatus.clear.severity < ObstacleStatus.near.severity, isTrue);
      expect(
          ObstacleStatus.near.severity < ObstacleStatus.danger.severity, isTrue);
    });

    test('tryParse 认不出返回 null，不猜档位', () {
      expect(ObstacleStatus.tryParse(' danger '), ObstacleStatus.danger);
      expect(ObstacleStatus.tryParse('危险'), isNull);
      expect(ObstacleStatus.tryParse(''), isNull);
    });
  });

  group('DeviceInfo · BLE 语义', () {
    Map<String, dynamic> base() => {
          'id': 7,
          'deviceSn': 'BC-2024-DEMO01',
          'name': '导盲杖',
          'online': true,
        };

    test('缺字段时全部退化为「未接入」', () {
      final device = DeviceInfo.fromJson(base());
      expect(device.bleConnected, isFalse);
      expect(device.bleAddress, isNull);
      expect(device.obstacle, isNull);
      expect(device.hasLiveObstacle, isFalse);
      expect(device.muted, isFalse);
    });

    test('断链时旧读数不算实时值 —— 这是最关键的语义', () {
      final device = DeviceInfo.fromJson({
        ...base(),
        'bleConnected': false,
        'obstacleStatus': 'DANGER',
        'obstacleDistanceCm': 12,
      });
      // 枚举仍解析得出（界面要显示"最后读数"）
      expect(device.obstacle, ObstacleStatus.danger);
      // 但绝不能当作当前状态，否则过期的"危险 12cm"会一直吓着家属
      expect(device.hasLiveObstacle, isFalse);
    });

    test('已连接且有读数才算实时', () {
      final device = DeviceInfo.fromJson({
        ...base(),
        'bleConnected': true,
        'obstacleStatus': 'near',
        'obstacleDistanceCm': 80,
        'obstacleSeconds': 2,
      });
      expect(device.hasLiveObstacle, isTrue);
      expect(device.obstacle, ObstacleStatus.near);
      expect(device.obstacleDistanceCm, 80);
      expect(device.obstacleSeconds, 2);
    });

    test('状态串认不出 → obstacle 为 null，界面显示「未知」', () {
      final device = DeviceInfo.fromJson({
        ...base(),
        'bleConnected': true,
        'obstacleStatus': 'WHATEVER',
      });
      expect(device.obstacle, isNull);
    });

    test('muteMode 1 才算静音，0/null 都是播报', () {
      expect(DeviceInfo.fromJson({...base(), 'muteMode': 1}).muted, isTrue);
      expect(DeviceInfo.fromJson({...base(), 'muteMode': 0}).muted, isFalse);
      expect(DeviceInfo.fromJson(base()).muted, isFalse);
    });

    test('时间字段非法不抛异常', () {
      final device = DeviceInfo.fromJson({
        ...base(),
        'bleConnectedAt': 'not-a-time',
        'obstacleReportedAt': '',
      });
      expect(device.bleConnectedAt, isNull);
      expect(device.obstacleReportedAt, isNull);
    });
  });

  group('DeviceStatusMessage · WebSocket 推送', () {
    test('解析 BLE 字段', () {
      final message = DeviceStatusMessage.fromJson({
        'online': true,
        'bleConnected': true,
        'obstacleStatus': 'CLEAR',
        'obstacleDistanceCm': 235,
        'muteMode': 1,
      });
      expect(message.bleConnected, isTrue);
      expect(message.obstacle, ObstacleStatus.clear);
      expect(message.hasLiveObstacle, isTrue);
      expect(message.obstacleDistanceCm, 235);
      expect(message.muteMode, 1);
    });

    test('旧版后端不带 BLE 字段时按未接入处理', () {
      final message = DeviceStatusMessage.fromJson({'online': false});
      expect(message.bleConnected, isFalse);
      expect(message.obstacle, isNull);
      expect(message.hasLiveObstacle, isFalse);
    });
  });

  group('DeviceCommandMessage / TelemetryAck', () {
    test('命令消息缺字段时不抛异常', () {
      final message = DeviceCommandMessage.fromJson({'command': 'M'});
      expect(message.command, 'M');
      expect(message.deviceId, 0);
      expect(message.issuedAt, 0);
      expect(message.commandName, isNull);
    });

    test('遥测回执：accepted=false 表示被节流丢弃，不是错误', () {
      final ack = TelemetryAck.fromJson({
        'accepted': false,
        'reason': 'throttled',
      });
      expect(ack.accepted, isFalse);
      expect(ack.reason, 'throttled');
    });
  });
}
