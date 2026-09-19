import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../state/location_state.dart';
import '../../state/ward_state.dart';
import '../location/location_map_canvas.dart';
import '../shared/widgets.dart';

/// 实时位置页（提示词 5.4）。
class LocationPage extends ConsumerStatefulWidget {
  const LocationPage({super.key});

  @override
  ConsumerState<LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends ConsumerState<LocationPage> {
  /// 每像素米数。档位是 1/2/5 的倍数，缩放手感才均匀。
  static const _zoomLevels = <double>[0.15, 0.3, 0.5, 1.0, 2.0, 5.0, 10.0];
  int _zoomIndex = 2;
  bool _autoCenter = true;

  double get _metersPerPixel => _zoomLevels[_zoomIndex];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(locationProvider);
    final ward = ref.watch(currentWardProvider);
    final latest = state.latest;

    return Scaffold(
      appBar: AppBar(
        title: const Text('实时位置'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: ward == null
                ? null
                : () => ref.read(locationProvider.notifier).load(ward.id),
          ),
        ],
      ),
      body: latest == null
          ? _EmptyBody(loading: state.loading, error: state.error)
          : Stack(
              children: [
                Positioned.fill(
                  child: LocationMapCanvas(
                    lng: latest.lng,
                    lat: latest.lat,
                    accuracyM: latest.accuracyM,
                    trail: state.trail,
                    metersPerPixel: _metersPerPixel,
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: 12,
                  child: _InfoBanner(
                    wardName: ward?.name ?? '',
                    state: state,
                    autoCenter: _autoCenter,
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 24,
                  child: Column(
                    children: [
                      _ZoomButton(
                        icon: Icons.add,
                        tooltip: '放大',
                        enabled: _zoomIndex > 0,
                        onPressed: () => setState(() => _zoomIndex--),
                      ),
                      const SizedBox(height: 10),
                      _ZoomButton(
                        icon: Icons.remove,
                        tooltip: '缩小',
                        enabled: _zoomIndex < _zoomLevels.length - 1,
                        onPressed: () => setState(() => _zoomIndex++),
                      ),
                      const SizedBox(height: 10),
                      _ZoomButton(
                        icon: _autoCenter ? Icons.my_location : Icons.location_searching,
                        tooltip: _autoCenter ? '已自动跟随' : '未自动跟随',
                        enabled: true,
                        highlighted: _autoCenter,
                        onPressed: () => setState(() => _autoCenter = !_autoCenter),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 16,
                  bottom: 24,
                  child: _TrailCard(trail: state.trail),
                ),
              ],
            ),
    );
  }
}

class _EmptyBody extends ConsumerWidget {
  const _EmptyBody({required this.loading, this.error});

  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return ErrorView(
        message: error!,
        onRetry: () {
          final wardId = ref.read(selectedWardIdProvider);
          if (wardId != null) {
            ref.read(locationProvider.notifier).load(wardId);
          }
        },
      );
    }
    return const EmptyState(
      icon: Icons.location_off_outlined,
      title: '暂未收到位置数据',
      description: '设备每隔 10 秒上报一次位置。\n若长时间没有数据，请检查设备是否在线。',
    );
  }
}

class _InfoBanner extends ConsumerWidget {
  const _InfoBanner({
    required this.wardName,
    required this.state,
    required this.autoCenter,
  });

  final String wardName;
  final LocationState state;
  final bool autoCenter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final latest = state.latest!;
    final stale = latest.isStale;
    final fmt = DateFormat('HH:mm:ss');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(wardName,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (stale ? AppTheme.warning : AppTheme.healthy)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    stale ? '数据已过期' : '实时跟随中',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: stale ? AppTheme.warning : AppTheme.healthy,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.place_outlined,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    latest.displayAddress,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _MetaText(
                  icon: Icons.schedule,
                  text: latest.reportedAtTime == null
                      ? '—'
                      : fmt.format(latest.reportedAtTime!),
                ),
                _MetaText(icon: Icons.timer_outlined, text: latest.freshnessText),
                if (latest.accuracyM != null)
                  _MetaText(
                    icon: Icons.gps_fixed,
                    text: '±${latest.accuracyM!.toStringAsFixed(0)}m',
                  ),
                if (latest.speed != null)
                  _MetaText(
                    icon: Icons.directions_walk,
                    text: '${latest.speed!.toStringAsFixed(1)} m/s',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
    this.highlighted = false,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: highlighted
            ? theme.colorScheme.primary
            : theme.colorScheme.surface.withValues(alpha: 0.94),
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            width: AppTheme.minTouchSize,
            height: AppTheme.minTouchSize,
            child: Icon(
              icon,
              size: 22,
              color: highlighted
                  ? theme.colorScheme.onPrimary
                  : enabled
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 轨迹点数量与时间范围——让家属知道"这段轨迹是什么时段的"。
class _TrailCard extends StatelessWidget {
  const _TrailCard({required this.trail});

  final List<TrailPoint> trail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (trail.length < 2) {
      return const SizedBox.shrink();
    }
    final fmt = DateFormat('HH:mm');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本次会话轨迹',
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            '${trail.length} 个点 · '
            '${fmt.format(trail.first.at)} → ${fmt.format(trail.last.at)}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
