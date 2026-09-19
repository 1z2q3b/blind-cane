import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../../models/alert.dart';
import '../../models/device_info.dart';
import '../../models/ward.dart';
import '../config/app_config.dart';
import '../storage/token_store.dart';

/// WebSocket 连接状态，用于在界面上给家属一个明确交代。
enum WsStatus { idle, connecting, connected, disconnected }

/// 实时推送客户端。
///
/// 订阅后端三个主题（提示词 7.3）：
/// - `/topic/ward/{id}/location` 位置更新
/// - `/topic/ward/{id}/alert`    告警
/// - `/topic/ward/{id}/device`   设备状态
///
/// 三个设计取舍：
/// 1. **自己管重连而不是用 StompConfig.reconnectDelay**：CONNECT 头里的 JWT 是
///    建立连接时定死的，用内置重连会在令牌过期后一直拿着旧令牌重试、
///    永远连不上。这里每次重连都重新构造 StompConfig，取最新的令牌。
/// 2. **退避到上限就放弃**：最多退到 30 秒一次，不再无限加速，
///    避免服务端挂了之后客户端还在高频打请求。
/// 3. **数据流用 broadcast**：同一个位置更新会同时被首页卡片、地图页、
///    轨迹折线三处消费，非广播流只能有一个监听者。
class GuardianWsClient {
  GuardianWsClient(this._store);

  final TokenStore _store;

  final _locationCtrl = StreamController<LatestLocation>.broadcast();
  final _alertCtrl = StreamController<AlertRecord>.broadcast();
  final _deviceCtrl = StreamController<DeviceStatusMessage>.broadcast();
  final _statusCtrl = StreamController<WsStatus>.broadcast();

  Stream<LatestLocation> get locations => _locationCtrl.stream;
  Stream<AlertRecord> get alerts => _alertCtrl.stream;
  Stream<DeviceStatusMessage> get deviceStatuses => _deviceCtrl.stream;
  Stream<WsStatus> get statuses => _statusCtrl.stream;

  StompClient? _client;
  int? _wardId;
  Timer? _reconnectTimer;
  int _retryCount = 0;
  bool _manuallyClosed = false;
  WsStatus _status = WsStatus.idle;

  WsStatus get status => _status;

  /// 连接并订阅某个被监护人的三个主题。
  ///
  /// 重复调用同一个 wardId 是幂等的；换 ward 会先断开旧订阅再连。
  void connect(int wardId) {
    if (_wardId == wardId && (_status == WsStatus.connected || _status == WsStatus.connecting)) {
      return;
    }
    _wardId = wardId;
    _manuallyClosed = false;
    _teardown();
    _start(wardId);
  }

  void disconnect() {
    _manuallyClosed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _teardown();
    _emitStatus(WsStatus.idle);
    _wardId = null;
  }

  void dispose() {
    disconnect();
    _locationCtrl.close();
    _alertCtrl.close();
    _deviceCtrl.close();
    _statusCtrl.close();
  }

  // ------------------------------------------------------------------

  void _start(int wardId) {
    final token = _store.accessToken;
    if (token == null || token.isEmpty) {
      // 没登录就别连了，否则服务端会在 CONNECT 阶段拒绝，日志里刷一片 ERROR
      _emitStatus(WsStatus.disconnected);
      return;
    }
    _emitStatus(WsStatus.connecting);

    final client = StompClient(
      config: StompConfig(
        url: AppConfig.wsUrl,
        // 后端是原生 WebSocket 端点（SimpleBroker），不走 SockJS
        useSockJS: false,
        // 令牌必须放在 STOMP 帧头里：WebSocket 握手阶段拿不到自定义 HTTP 头，
        // 后端的 StompAuthChannelInterceptor 正是从 CONNECT 帧的 Authorization 里取
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        // 心跳与服务端 WebSocketConfig 的 30s 对齐；客户端额外声明接受服务端心跳
        heartbeatOutgoing: const Duration(seconds: 30),
        heartbeatIncoming: const Duration(seconds: 30),
        connectionTimeout: const Duration(seconds: 10),
        // 交给自己的重连逻辑，内置重连固定用首次的令牌，过期后永远连不上
        reconnectDelay: Duration.zero,
        onConnect: (frame) => _onConnect(frame, wardId),
        onDisconnect: (frame) => _onDisconnect(),
        onWebSocketError: (error) {
          debugPrint('[WS] 连接错误: $error');
          _onDisconnect();
        },
        onWebSocketDone: () => _onDisconnect(),
        onStompError: (frame) {
          // 服务端的订阅鉴权拒绝会走到这里（ERROR 帧：无该被监护人的监护权限）。
          // 这种情况重连没有意义，直接停掉，避免无意义的重连风暴。
          debugPrint('[WS] STOMP ERROR: ${frame.headers['message']} ${frame.body}');
          _manuallyClosed = true;
          _reconnectTimer?.cancel();
          _emitStatus(WsStatus.disconnected);
        },
      ),
    );
    _client = client;
    client.activate();
  }

  void _onConnect(StompFrame frame, int wardId) {
    debugPrint('[WS] 已连接 ward=$wardId');
    _retryCount = 0;
    _emitStatus(WsStatus.connected);

    _client?.subscribe(
      destination: '/topic/ward/$wardId/location',
      callback: (f) => _emit(_locationCtrl, f.body, LatestLocation.fromJson),
    );
    _client?.subscribe(
      destination: '/topic/ward/$wardId/alert',
      callback: (f) => _emit(_alertCtrl, f.body, AlertRecord.fromJson),
    );
    _client?.subscribe(
      destination: '/topic/ward/$wardId/device',
      callback: (f) => _emit(_deviceCtrl, f.body, DeviceStatusMessage.fromJson),
    );
  }

  void _onDisconnect() {
    _teardown();
    _emitStatus(WsStatus.disconnected);
    if (_manuallyClosed || _wardId == null) {
      return;
    }
    _scheduleReconnect(_wardId!);
  }

  void _scheduleReconnect(int wardId) {
    _reconnectTimer?.cancel();
    _retryCount = min(_retryCount + 1, 6);
    final delay = Duration(seconds: min(30, 1 << (_retryCount - 1)));
    debugPrint('[WS] ${delay.inSeconds}s 后重连（第 $_retryCount 次）');
    _reconnectTimer = Timer(delay, () {
      if (_manuallyClosed || _wardId != wardId) {
        return;
      }
      _emitStatus(WsStatus.connecting);
      _start(wardId);
    });
  }

  /// 解析一帧 body 并推入对应数据流。
  ///
  /// 解析失败只打日志不抛：服务端字段演进时，一条解析不了的消息
  /// 不应该把整个订阅回调打断（回调抛异常会导致该订阅后续消息静默丢失）。
  void _emit<T>(
    StreamController<T> controller,
    String? body,
    T Function(Map<String, dynamic>) parse,
  ) {
    if (body == null || body.isEmpty) {
      return;
    }
    try {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic> && !controller.isClosed) {
        controller.add(parse(json));
      }
    } catch (e) {
      debugPrint('[WS] 消息解析失败: $e, body=$body');
    }
  }

  void _teardown() {
    final client = _client;
    _client = null;
    if (client == null) {
      return;
    }
    try {
      client.deactivate();
    } catch (e) {
      debugPrint('[WS] 断开时异常（可忽略）: $e');
    }
  }

  void _emitStatus(WsStatus status) {
    if (_status == status) {
      return;
    }
    _status = status;
    if (!_statusCtrl.isClosed) {
      _statusCtrl.add(status);
    }
  }
}
