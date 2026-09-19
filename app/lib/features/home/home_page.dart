import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../models/device_info.dart';
import '../../models/ward.dart';
import '../../state/alert_state.dart';
import '../../state/location_state.dart';
import '../../state/providers.dart';
import '../../state/ward_state.dart';
import '../location/location_map_canvas.dart';
import '../shared/ward_switcher.dart';
import '../shared/widgets.dart';
import 'main_shell.dart';

/// 首页：一屏之内回答家属最关心的三个问题
/// 「他在哪 / 他安全吗 / 有没有事找我」。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wards = ref.watch(wardListProvider);
    final current = ref.watch(currentWardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const WardSwitcher(),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(wardListProvider.notifier).refresh();
              final wardId = ref.read(selectedWardIdProvider);
              if (wardId != null) {
                ref.read(locationProvider.notifier).load(wardId);
              }
              ref.read(pendingCountProvider.notifier).refresh();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const WsStatusBanner(),
          Expanded(
            child: wards.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(
                message: '加载家人档案失败\n$e',
                onRetry: () => ref.read(wardListProvider.notifier).refresh(),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.person_add_alt_1,
                    title: '还没有添加家人',
                    description: '添加被监护的家人并绑定导盲杖设备后，就能看到实时位置与告警',
                    action: FilledButton.icon(
                      onPressed: () => context.push('/wards/new'),
                      icon: const Icon(Icons.add),
                      label: const Text('添加家人'),
                    ),
                  );
                }
                if (current == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _HomeBody(ward: current);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody({required this.ward});

  final Ward ward;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(liveDeviceProvider) ?? ward.device;
    final locationState = ref.watch(locationProvider);
    final pendingCount = ref.watch(currentWardPendingCountProvider);

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(wardListProvider.notifier).refresh();
        await ref.read(locationProvider.notifier).load(ward.id);
        await ref.read(pendingCountProvider.notifier).refresh();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _HeaderCard(ward: ward, device: device),
          const SectionTitle(title: '实时位置'),
          _LocationCard(ward: ward, locationState: locationState, device: device),
          if (pendingCount > 0) ...[
            const SectionTitle(title: '待处理'),
            _AlertSummaryCard(count: pendingCount),
          ],
          const SectionTitle(title: '快捷操作'),
          _QuickActions(ward: ward),
          if (AppConfig.demoMode) ...[
            const SectionTitle(title: '演示工具'),
            _DemoPanel(ward: ward),
          ],
        ],
      ),
    );
  }
}

/// 顶部状态卡：把「这个人 / 这台设备现在什么状态」压缩成一眼可读的一行。
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.ward, required this.device});

  final Ward ward;
  final DeviceInfo? device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final age = ward.age;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    ward.name.isNotEmpty ? ward.name.substring(0, 1) : '?',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ward.name,
                        style: const TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (ward.relation != null) ward.relation!,
                          if (age != null) '$age 岁',
                          if (ward.isPrimaryGuardian) '主监护人',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '家人档案',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => context.push('/wards/${ward.id}'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (device == null)
              _NoDeviceHint(wardId: ward.id)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OnlineBadge(
                    online: device!.online,
                    text: device!.lastOnlineText,
                  ),
                  BatteryBadge(device: device),
                  SignalBadge(level: device!.signalLevel),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _NoDeviceHint extends StatelessWidget {
  const _NoDeviceHint({required this.wardId});

  final int wardId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.link_off, color: theme.colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '尚未绑定导盲杖，绑定后才能接收位置与告警',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: () => context.push('/wards/$wardId'),
            child: const Text('去绑定'),
          ),
        ],
      ),
    );
  }
}

/// 位置卡：地址 + 新鲜度 + 地图缩略图。
class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.ward,
    required this.locationState,
    required this.device,
  });

  final Ward ward;
  final LocationState locationState;
  final DeviceInfo? device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = locationState.latest;

    if (latest == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              if (locationState.loading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.location_searching, color: theme.colorScheme.outline),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  locationState.error ??
                      (device == null ? '绑定设备后即可查看位置' : '等待设备上报位置…'),
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final stale = latest.isStale;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 190,
            child: Stack(
              children: [
                Positioned.fill(
                  child: LocationMapCanvas(
                    lng: latest.lng,
                    lat: latest.lat,
                    accuracyM: latest.accuracyM,
                    trail: locationState.trail,
                    metersPerPixel: 0.45,
                    showCoordinates: false,
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: _Chip(
                    text: stale ? '数据可能已过期' : '实时',
                    color: stale ? AppTheme.warning : AppTheme.healthy,
                  ),
                ),
                if (stale)
                  Positioned(
                    right: 10,
                    top: 10,
                    child: _Chip(text: latest.freshnessText, color: null),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.place_outlined,
                              size: 18, color: theme.colorScheme.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              latest.displayAddress,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          latest.freshnessText,
                          if (latest.accuracyM != null)
                            '精度 ±${latest.accuracyM!.toStringAsFixed(0)}m',
                          if (locationState.trail.length > 1)
                            '本次已记录 ${locationState.trail.length} 个轨迹点',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => context.push('/location'),
                  icon: const Icon(Icons.open_in_full, size: 18),
                  label: const Text('查看'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: color != null ? FontWeight.w600 : FontWeight.w400,
          color: color ?? theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _AlertSummaryCard extends ConsumerWidget {
  const _AlertSummaryCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: ListTile(
        leading: Icon(Icons.warning_amber_rounded,
            color: theme.colorScheme.onErrorContainer, size: 30),
        title: Text(
          '有 $count 条告警待处理',
          style: TextStyle(
            color: theme.colorScheme.onErrorContainer,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        trailing:
            Icon(Icons.chevron_right, color: theme.colorScheme.onErrorContainer),
        // 直接切底部 Tab 而不是 push 新页面：push 后底部导航会失去高亮，
        // 用户会以为进了死胡同，而"告警"本该是 Tab 平级的内容
        onTap: () => ref.read(mainTabProvider.notifier).select(1),
      ),
    );
  }
}

/// 快捷操作。
class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.ward});

  final Ward ward;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: const Text('查看实时位置'),
            subtitle: const Text('放大查看地图与最近轨迹'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/location'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.notifications_none),
            title: const Text('告警中心'),
            subtitle: const Text('查看历史告警与处理记录'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => ref.read(mainTabProvider.notifier).select(1),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('家人档案与设备'),
            subtitle: Text(
              ward.device == null ? '未绑定设备' : '已绑定 ${ward.device!.deviceSn}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/wards/${ward.id}'),
          ),
        ],
      ),
    );
  }
}

/// 演示面板：把提示词 6.6 的 Mock 动作做成按钮，答辩时不用敲 curl。
class _DemoPanel extends ConsumerWidget {
  const _DemoPanel({required this.ward});

  final Ward ward;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sn = ward.device?.deviceSn;
    if (sn == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '该家人尚未绑定设备，无法触发模拟动作。演示设备 SN：BC-2024-DEMO01',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final repository = ref.read(repositoryProvider);

    Future<void> run(String label, Future<void> Function() action) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await action();
        messenger.showSnackBar(SnackBar(content: Text('$label 已触发')));
      } catch (e) {
        messenger.showSnackBar(SnackBar(
          content: Text('$label 失败：$e'),
          backgroundColor: theme.colorScheme.error,
        ));
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '设备 $sn · 生产环境随模拟器关闭而消失',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.critical,
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: () =>
                      run('一键求助', () => repository.mockSos(sn)),
                  icon: const Icon(Icons.sos, size: 20),
                  label: const Text('模拟 SOS'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.warning,
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: () =>
                      run('跌倒检测', () => repository.mockFall(sn)),
                  icon: const Icon(Icons.personal_injury, size: 20),
                  label: const Text('模拟跌倒'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () => run('切离线',
                      () => repository.mockToggleOnline(sn, ageMinutes: 6)),
                  icon: const Icon(Icons.wifi_off, size: 20),
                  label: const Text('让设备离线'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () =>
                      run('恢复在线', () => repository.mockToggleOnline(sn)),
                  icon: const Icon(Icons.wifi, size: 20),
                  label: const Text('恢复在线'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () =>
                      run('电量置低', () => repository.mockBattery(sn, 18)),
                  icon: const Icon(Icons.battery_alert, size: 20),
                  label: const Text('电量压到 18%'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
