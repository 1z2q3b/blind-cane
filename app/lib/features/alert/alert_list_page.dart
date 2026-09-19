import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/alert.dart';
import '../../state/alert_state.dart';
import '../../state/ward_state.dart';
import '../shared/widgets.dart';

/// 告警中心列表（提示词 5.6）。
class AlertListPage extends ConsumerStatefulWidget {
  const AlertListPage({super.key});

  @override
  ConsumerState<AlertListPage> createState() => _AlertListPageState();
}

class _AlertListPageState extends ConsumerState<AlertListPage> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    // 距底部 300px 就预加载：等到真正触底才请求，家属会看到一段空白
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      ref.read(alertListProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(alertFilterProvider);
    final listState = ref.watch(alertListProvider);
    final wards = ref.watch(wardListProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('告警中心'),
        actions: [
          IconButton(
            tooltip: '重置筛选',
            icon: const Icon(Icons.filter_alt_off_outlined),
            onPressed: filter.isEmpty
                ? null
                : () => ref.read(alertFilterProvider.notifier).reset(),
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(wards: wards),
          const Divider(height: 1),
          Expanded(
            child: listState.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(
                message: '加载告警失败\n$e',
                onRetry: () => ref.read(alertListProvider.notifier).refresh(),
              ),
              data: (state) {
                if (state.items.isEmpty) {
                  return EmptyState(
                    icon: Icons.notifications_off_outlined,
                    title: filter.isEmpty ? '还没有告警记录' : '没有符合条件的告警',
                    description: filter.isEmpty
                        ? '设备产生的告警会自动出现在这里'
                        : '试试切换筛选条件',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () =>
                      ref.read(alertListProvider.notifier).refresh(),
                  child: ListView.separated(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    itemCount: state.items.length + (state.hasMore ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      if (index >= state.items.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      return _AlertCard(alert: state.items[index]);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.wards});

  final List<dynamic> wards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(alertFilterProvider);
    final notifier = ref.read(alertFilterProvider.notifier);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _StatusChip(
            label: '全部',
            selected: filter.status == null,
            onSelected: () => notifier.setStatus(null),
          ),
          _StatusChip(
            label: '待处理',
            selected: filter.status == AlertRecord.statusPending,
            onSelected: () => notifier.setStatus(AlertRecord.statusPending),
          ),
          _StatusChip(
            label: '已处理',
            selected: filter.status == AlertRecord.statusResolved,
            onSelected: () => notifier.setStatus(AlertRecord.statusResolved),
          ),
          _StatusChip(
            label: '误报',
            selected: filter.status == AlertRecord.statusFalseAlarm,
            onSelected: () => notifier.setStatus(AlertRecord.statusFalseAlarm),
          ),
          const SizedBox(width: 12),
          PopupMenuButton<String?>(
            tooltip: '按类型筛选',
            onSelected: notifier.setType,
            itemBuilder: (context) => [
              const PopupMenuItem(value: null, child: Text('全部类型')),
              for (final kind in AlertKind.values)
                if (kind != AlertKind.unknown)
                  PopupMenuItem(value: kind.code, child: Text(kind.label)),
            ],
            child: _MenuChip(
              label: filter.type == null
                  ? '类型'
                  : AlertKind.fromCode(filter.type).label,
              active: filter.type != null,
            ),
          ),
          if (wards.length > 1) ...[
            const SizedBox(width: 8),
            PopupMenuButton<int?>(
              tooltip: '按家人筛选',
              onSelected: notifier.setWard,
              itemBuilder: (context) => [
                const PopupMenuItem(value: null, child: Text('全部家人')),
                for (final ward in wards)
                  PopupMenuItem(value: ward.id as int, child: Text(ward.name as String)),
              ],
              child: _MenuChip(
                label: filter.wardId == null
                    ? '家人'
                    : wards
                        .firstWhere(
                          (w) => w.id == filter.wardId,
                          orElse: () => wards.first,
                        )
                        .name as String,
                active: filter.wardId != null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _MenuChip extends StatelessWidget {
  const _MenuChip({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: active
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 15)),
          const Icon(Icons.arrow_drop_down, size: 20),
        ],
      ),
    );
  }
}

/// 单条告警卡片。
class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final AlertRecord alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AppTheme.severityColor(alert.severity, theme.colorScheme);
    final timeText = alert.createdAt == null
        ? ''
        : DateFormat('MM-dd HH:mm').format(alert.createdAt!);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/alerts/${alert.id}'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左侧色条：列表快速扫视时靠颜色分级比读文字快得多
            Container(width: 6, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_iconOf(alert.kind), size: 20, color: color),
                        const SizedBox(width: 8),
                        Text(
                          alert.kind.label,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusTag(alert: alert),
                        const Spacer(),
                        Text(
                          timeText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (alert.wardName != null && alert.wardName!.isNotEmpty)
                      Text(
                        alert.wardName!,
                        style: const TextStyle(fontSize: 15),
                      ),
                    if (alert.address != null && alert.address!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(Icons.place_outlined,
                                size: 15, color: theme.colorScheme.outline),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                alert.address!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (alert.note != null && alert.note!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          alert.note!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (alert.isAwaitingConfirm)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _ConfirmHint(theme: theme),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconOf(AlertKind kind) {
    return switch (kind) {
      AlertKind.sos => Icons.sos,
      AlertKind.fall => Icons.personal_injury,
      AlertKind.offline => Icons.wifi_off,
      AlertKind.lowBattery => Icons.battery_alert,
      AlertKind.geofenceExit => Icons.logout,
      AlertKind.geofenceEnter => Icons.login,
      AlertKind.unknown => Icons.notifications,
    };
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.alert});

  final AlertRecord alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = switch (alert.status) {
      AlertRecord.statusResolved => (
          AppTheme.healthy.withValues(alpha: 0.14),
          AppTheme.healthy,
        ),
      AlertRecord.statusFalseAlarm => (
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant,
        ),
      _ => (
          theme.colorScheme.errorContainer,
          theme.colorScheme.onErrorContainer,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        alert.statusLabel,
        style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ConfirmHint extends StatelessWidget {
  const _ConfirmHint({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 16, color: AppTheme.warning),
          const SizedBox(width: 6),
          const Text(
            '疑似事件待确认，超时将自动升级',
            style: TextStyle(fontSize: 13, color: AppTheme.warning),
          ),
        ],
      ),
    );
  }
}
