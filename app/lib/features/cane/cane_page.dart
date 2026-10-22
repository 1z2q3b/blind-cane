import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/ble_protocol.dart';
import '../../core/ble/cane_connection.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../models/device_info.dart';
import '../../state/cane_state.dart';
import '../../state/providers.dart';
import '../shared/widgets.dart';

/// 手杖连接与实时避障页。
///
/// 这一页要回答的是「手机和手杖到底通没通、手杖现在看到什么」——
/// 在接入 BLE 之前，家属端只有「设备在线/离线」，看不到手杖本体的即时感知。
class CanePage extends ConsumerWidget {
  const CanePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(caneSessionProvider);
    final device = ref.watch(caneTargetDeviceProvider);
    final notifier = ref.read(caneSessionProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('手杖连接'),
        actions: [
          IconButton(
            tooltip: '清除提示',
            icon: const Icon(Icons.notifications_off_outlined),
            onPressed: session.error == null && session.commandHint == null
                ? null
                : notifier.acknowledgeHint,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (session.error != null)
            _Banner(
              icon: Icons.error_outline,
              text: session.error!,
              color: AppTheme.critical,
            ),
          if (session.commandHint != null)
            _Banner(
              icon: Icons.campaign_outlined,
              text: session.commandHint!,
              color: AppTheme.healthy,
            ),
          _SourceCard(session: session, onChanged: notifier.setSource),
          const SectionTitle(title: '链路状态'),
          _LinkCard(session: session, device: device, notifier: notifier),
          const SectionTitle(title: '前方障碍'),
          _ObstacleCard(session: session, device: device),
          const SectionTitle(title: '手杖模式'),
          _MuteCard(session: session, device: device, notifier: notifier),
          const SectionTitle(title: '扫描手杖'),
          _ScanCard(session: session, device: device, notifier: notifier),
          if (AppConfig.demoMode) ...[
            const SectionTitle(title: '演示工具'),
            _DemoCard(device: device),
          ],
          const SectionTitle(title: '链路诊断'),
          _DiagnosticsCard(session: session),
        ],
      ),
    );
  }
}

/// 数据来源切换。
///
/// 做成显式的开关而不是自动判断，是因为「接不上」和「用模拟」是两件事：
/// 现场必须能一眼看出当前到底在跟真机通信还是在跟本机模拟通信，
/// 否则答辩时会分不清"演示成功"到底证明了什么。
class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.session, required this.onChanged});

  final CaneSessionState session;
  final ValueChanged<CaneSource> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('数据来源', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '真机 = 手机直连 ESP32-S3（广播名 ${BleProtocol.deviceName}）；'
              '模拟 = 本机扮演手杖推送报文，其余链路完全一致',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<CaneSource>(
              segments: const [
                ButtonSegment(
                  value: CaneSource.real,
                  icon: Icon(Icons.bluetooth),
                  label: Text('真机'),
                ),
                ButtonSegment(
                  value: CaneSource.mock,
                  icon: Icon(Icons.smart_toy_outlined),
                  label: Text('模拟'),
                ),
              ],
              selected: {session.source},
              onSelectionChanged: (values) => onChanged(values.first),
            ),
          ],
        ),
      ),
    );
  }
}

/// 链路状态与连接操作。
class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.session,
    required this.device,
    required this.notifier,
  });

  final CaneSessionState session;
  final DeviceInfo? device;
  final CaneSessionNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _linkColor(session.link);
    final address = session.bleAddress ?? device?.bleAddress;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_linkIcon(session.link), color: color, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _linkLabel(session.link),
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        address == null
                            ? '尚未选择手杖'
                            : '$address${session.rssi == null ? '' : ' · ${session.rssi} dBm'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (session.connectedButSilent) ...[
              const SizedBox(height: 12),
              Text(
                '链路已建立，但还没有收到任何遥测帧。请确认手杖已上电并正在推送 —— '
                '服务发现成功不代表 TX 通知在推数据。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppTheme.warning),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, AppTheme.minTouchSize),
                    ),
                    onPressed: session.busy || address == null
                        ? null
                        : () => notifier.connect(address),
                    icon: const Icon(Icons.bluetooth_connected),
                    label: Text(session.connecting ? '连接中…' : '连接手杖'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, AppTheme.minTouchSize),
                    ),
                    onPressed: session.connected
                        ? notifier.disconnect
                        : null,
                    icon: const Icon(Icons.bluetooth_disabled),
                    label: const Text('断开'),
                  ),
                ),
              ],
            ),
            if (address == null && device == null) ...[
              const SizedBox(height: 10),
              Text(
                '当前家人还没绑定导盲杖。请先在「家人档案」里按 SN 绑定，'
                '或先在下方扫描并连接一台手杖。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _linkLabel(CaneLinkState state) => switch (state) {
        CaneLinkState.idle => '未连接',
        CaneLinkState.scanning => '扫描中',
        CaneLinkState.connecting => '连接中…',
        CaneLinkState.connected => '已连接 · 实时接收中',
        CaneLinkState.disconnected => '连接已断开',
      };

  static IconData _linkIcon(CaneLinkState state) => switch (state) {
        CaneLinkState.connected => Icons.bluetooth_connected,
        CaneLinkState.connecting => Icons.bluetooth_searching,
        CaneLinkState.scanning => Icons.bluetooth_searching,
        _ => Icons.bluetooth_disabled,
      };

  static Color _linkColor(CaneLinkState state) => switch (state) {
        CaneLinkState.connected => AppTheme.healthy,
        CaneLinkState.connecting || CaneLinkState.scanning => AppTheme.warning,
        _ => AppTheme.critical,
      };
}

/// 障碍指示卡：这一页最核心的视觉信息。
class _ObstacleCard extends StatelessWidget {
  const _ObstacleCard({required this.session, required this.device});

  final CaneSessionState session;
  final DeviceInfo? device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 本地帧最新（500ms 一帧），优先用它；没有本地帧时退回云端值
    ObstacleStatus? status;
    int? distanceCm;
    var stale = false;

    final local = session.latest;
    if (session.connected && local != null) {
      status = local.status;
      distanceCm = local.distanceCm;
    } else {
      status = device?.obstacle;
      distanceCm = device?.obstacleDistanceCm;
      // 关键判断：链路断开时障碍值只是「最后读数」，绝不能当实时值渲染
      stale = status != null && !(device?.bleConnected ?? false);
    }

    final color = _statusColor(status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stale)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _Banner(
                  icon: Icons.history_toggle_off,
                  text: '蓝牙已断开，以下是最后一次读数，不代表当前路况',
                  color: AppTheme.warning,
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  distanceCm == null ? '--' : '$distanceCm',
                  style: TextStyle(
                    fontSize: 54,
                    height: 1.0,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'cm',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status?.label ?? '未知',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _explain(status),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              session.connected
                  ? '本次连接已接收 ${session.frameCount} 帧，原始报文：'
                      '${session.latest?.raw ?? '—'}'
                  : '连接手杖后可看到 500ms 刷新的实时测距',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _explain(ObstacleStatus? status) => switch (status) {
        ObstacleStatus.clear =>
          '前方 ≥ ${BleProtocol.nearCm}cm，手杖蜂鸣器静音',
        ObstacleStatus.near =>
          '前方 ${BleProtocol.dangerCm}~${BleProtocol.nearCm}cm，手杖断续鸣叫提醒',
        ObstacleStatus.danger =>
          '前方 < ${BleProtocol.dangerCm}cm，手杖急促短鸣，请立即停下',
        null => '尚未收到障碍遥测。确认手杖已上电、蓝牙已连接。',
      };

  static Color _statusColor(ObstacleStatus? status) => switch (status) {
        ObstacleStatus.clear => AppTheme.healthy,
        ObstacleStatus.near => AppTheme.warning,
        ObstacleStatus.danger => AppTheme.critical,
        null => Colors.grey,
      };
}

/// 静音模式：家属侧按钮。
class _MuteCard extends StatelessWidget {
  const _MuteCard({
    required this.session,
    required this.device,
    required this.notifier,
  });

  final CaneSessionState session;
  final DeviceInfo? device;
  final CaneSessionNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = device?.muted ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              muted ? '手杖当前：静音' : '手杖当前：播报',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '切换命令不是直接写蓝牙：它先到云端、再由本机（持有链路的这台手机）'
              '写入手杖的 RX 特征，回执成功云端才会认定模式已变。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, AppTheme.minTouchSize),
                  backgroundColor:
                      muted ? AppTheme.warning : theme.colorScheme.primary,
                ),
                onPressed: session.connected ? notifier.toggleMute : null,
                icon: Icon(muted ? Icons.volume_up : Icons.volume_off),
                label: Text(muted ? '恢复播报' : '切换静音'),
              ),
            ),
            if (!session.connected) ...[
              const SizedBox(height: 8),
              Text(
                '手杖未连接，命令无法下发（会无人执行）。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppTheme.warning),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 扫描与结果列表。
class _ScanCard extends ConsumerWidget {
  const _ScanCard({
    required this.session,
    required this.device,
    required this.notifier,
  });

  final CaneSessionState session;
  final DeviceInfo? device;
  final CaneSessionNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final results = session.scanResults;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppTheme.minTouchSize),
                ),
                onPressed: session.busy ? null : notifier.scan,
                icon: session.scanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(session.scanning ? '扫描中…' : '扫描附近手杖'),
              ),
            ),
            if (session.source == CaneSource.real) ...[
              const SizedBox(height: 10),
              Text(
                '扫描需要系统授予「附近的设备」权限；Android 12 以下还需要定位权限。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (results.isEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '暂无扫描结果。若手杖已上电仍扫不到，请确认它正在广播'
                '（名称 ${BleProtocol.deviceName}）且距离在 3 米内。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            for (final cane in results) ...[
              const SizedBox(height: 12),
              _CaneTile(
                cane: cane,
                isBoundAddress: device?.bleAddress != null &&
                    device!.bleAddress!.toUpperCase() == cane.bleAddress,
                onConnect: () => notifier.connect(cane.bleAddress),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CaneTile extends StatelessWidget {
  const _CaneTile({
    required this.cane,
    required this.isBoundAddress,
    required this.onConnect,
  });

  final DiscoveredCane cane;
  final bool isBoundAddress;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.bluetooth, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      cane.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    if (isBoundAddress)
                      _Tag(text: '已登记', color: AppTheme.healthy)
                    else if (cane.registered)
                      _Tag(text: '云端已有档案', color: theme.colorScheme.primary)
                    else
                      _Tag(text: '未登记', color: AppTheme.warning),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${cane.bleAddress} · 信号 ${cane.signalLevel}/4',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onConnect, child: const Text('连接')),
        ],
      ),
    );
  }
}

/// 演示工具：直接让后端灌一帧，用来看服务端节流与「距离优先」。
class _DemoCard extends ConsumerWidget {
  const _DemoCard({required this.device});

  final DeviceInfo? device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sn = device?.deviceSn;
    if (sn == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '当前家人未绑定设备，无法使用演示工具。演示设备 SN：BC-2024-DEMO01',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    final repository = ref.read(repositoryProvider);

    Future<void> push(String label, int distanceCm) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        final ack = await repository.mockBleTelemetry(sn, distanceCm: distanceCm);
        messenger.showSnackBar(SnackBar(
          content: Text(ack.accepted
              ? '$label 已采纳：云端记录 ${ack.obstacleStatus} ${ack.distanceCm}cm'
              : '$label 被节流丢弃（${ack.reason}）'),
        ));
      } catch (e) {
        messenger.showSnackBar(SnackBar(
          content: Text('$label 失败：$e'),
          backgroundColor: theme.colorScheme.error,
        ));
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '只传距离，状态由后端按阈值推导 —— 用来验证「距离优先于状态」。'
              '同一个值连点两次，第二次多半会被 1 秒窗口节流丢弃。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton(
                  onPressed: () => push('畅通 235cm', 235),
                  child: const Text('畅通 235cm'),
                ),
                OutlinedButton(
                  onPressed: () => push('有障碍 80cm', 80),
                  child: const Text('有障碍 80cm'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.critical,
                  ),
                  onPressed: () => push('危险 12cm', 12),
                  child: const Text('危险 12cm'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 诊断信息：把节流效果摆出来，便于现场解释「为什么没有每帧都发」。
class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({required this.session});

  final CaneSessionState session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final at = session.lastForwardedAt;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('接收帧数', '${session.frameCount}（手杖 500ms 一帧）'),
            _row('已转发云端', '${session.forwardedCount} 次'),
            _row('被节流丢弃', '${session.droppedCount} 次'),
            _row('最近转发', at == null ? '—' : _ago(at)),
            const SizedBox(height: 8),
            Text(
              '本机节流策略：状态变化立即转发 + 距离跳变 ≥20cm + 30 秒心跳；'
              '服务端另有 1 秒窗口兜底，因此稳态下部分帧会被丢弃，属正常行为。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _ago(DateTime at) {
    final seconds = DateTime.now().difference(at).inSeconds;
    if (seconds < 60) {
      return '$seconds 秒前';
    }
    return '${seconds ~/ 60} 分钟前';
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 104,
              child: Text(label, style: const TextStyle(fontSize: 15)),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                height: 1.35,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
