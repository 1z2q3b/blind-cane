import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/geofence.dart';
import '../../state/geofence_state.dart';
import '../../state/location_state.dart';
import '../../state/ward_state.dart';
import '../../core/map/smart_map_view.dart';

/// 轨迹回放页。
///
/// <p>设计取舍：
/// <ul>
///   <li>**画在现有的 [LocationMapCanvas] 上**而不是另起一套渲染。一期已经用它
///       做过实时位置，坐标投影逻辑复用即可，回放只是"把 trail 的前 N 个点画出来"。</li>
///   <li>**缩放按当天轨迹的包围盒动态算**。固定 0.6 米/像素在屋里走动时刚好，
///       但老人坐车去趟医院跨了 5 公里，固定缩放会让整条轨迹缩成一个点。</li>
///   <li>**播放节奏按固定间隔推进**，不按真实时间间隔。因为上报是 10 秒一次，
///       若按真实间隔播，中途任何一次设备离线都会让回放卡住不动几十秒，
///       演示时观感很差。倍速档位就是给人调的补偿手段。</li>
/// </ul>
class TrackPlaybackPage extends ConsumerStatefulWidget {
  const TrackPlaybackPage({super.key});

  @override
  ConsumerState<TrackPlaybackPage> createState() => _TrackPlaybackPageState();
}

class _TrackPlaybackPageState extends ConsumerState<TrackPlaybackPage> {
  Timer? _timer;
  int _index = 0;
  bool _playing = false;
  double _speed = 1;

  /// 每个点位停留的基础时长（毫秒），再除以倍速。
  static const int _baseTickMs = 320;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(milliseconds: (_baseTickMs / _speed).round()),
      (_) {
        final points = ref.read(trackProvider).value ?? const <TrackPoint>[];
        if (points.isEmpty) {
          return;
        }
        if (_index >= points.length - 1) {
          _stop();
          return;
        }
        setState(() => _index += 1);
      },
    );
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (mounted) {
      setState(() => _playing = false);
    } else {
      _playing = false;
    }
  }

  void _toggle(List<TrackPoint> points) {
    if (points.isEmpty) {
      return;
    }
    if (_playing) {
      _stop();
      return;
    }
    // 播到结尾后再点播放，从头开始，省得用户自己把进度条拖回 0
    if (_index >= points.length - 1) {
      setState(() => _index = 0);
    }
    setState(() => _playing = true);
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(trackProvider);
    final ward = ref.watch(currentWardProvider);
    final day = ref.watch(trackDateProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(ward == null ? '轨迹回放' : '${ward.name} · 轨迹回放'),
        actions: [
          TextButton.icon(
            onPressed: () => _pickDate(context),
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text('${day.month}月${day.day}日'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 56),
                const SizedBox(height: 16),
                Text('加载轨迹失败：$error', textAlign: TextAlign.center),
                const SizedBox(height: 20),
                // 全宽 CTA：主题 minimumSize 宽度为 0，全宽靠 SizedBox 撑
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => ref.read(trackProvider.notifier).reload(),
                    child: const Text('重试'),
                  ),
                ),
              ],
            ),
          ),
        ),
        data: (points) => _buildBody(points),
      ),
    );
  }

  Widget _buildBody(List<TrackPoint> points) {
    if (points.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.route_outlined,
                  size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text('这一天没有轨迹记录', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '手杖上报位置后才会产生轨迹。\n可以换一天看看，或先确认设备在线。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    // 播放进度不超过点数范围（切换日期后点数可能变少）
    final safeIndex = _index.clamp(0, points.length - 1);
    final current = points[safeIndex];
    final visible = points.take(safeIndex + 1).toList(growable: false);

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final mpp = _metersPerPixel(points, constraints.maxWidth,
                  constraints.maxHeight);
              return SmartMapView(
                lng: current.lng,
                lat: current.lat,
                accuracyM: current.accuracyM,
                trail: [
                  for (final p in visible)
                    TrailPoint(
                      lng: p.lng,
                      lat: p.lat,
                      at: p.at ?? DateTime.now(),
                    ),
                ],
                metersPerPixel: mpp,
              );
            },
          ),
        ),
        _buildControls(points, safeIndex, current),
      ],
    );
  }

  Widget _buildControls(List<TrackPoint> points, int index, TrackPoint current) {
    final theme = Theme.of(context);
    final total = points.length;
    final at = current.at;

    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.place_outlined,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    at == null
                        ? '第 ${index + 1} / $total 个点'
                        : '${_hhmmss(at)}  ·  第 ${index + 1}/$total 点',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (current.speed != null)
                    Text(
                      '${(current.speed! * 3.6).toStringAsFixed(1)} km/h',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
              Slider(
                value: index.toDouble(),
                min: 0,
                max: (total - 1).toDouble(),
                divisions: total > 1 ? total - 1 : null,
                onChanged: (v) {
                  _stop();
                  setState(() => _index = v.round());
                },
              ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _toggle(points),
                      icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                      label: Text(_playing ? '暂停' : '播放'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<double>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(value: 1.0, label: Text('1x')),
                      ButtonSegment(value: 2.0, label: Text('2x')),
                      ButtonSegment(value: 4.0, label: Text('4x')),
                    ],
                    selected: {_speed},
                    onSelectionChanged: (s) {
                      setState(() => _speed = s.first);
                      // 节奏变了要重建定时器，否则倍速要等下一轮才生效
                      if (_playing) {
                        _startTimer();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '共 $total 个点 · 约 ${_totalKm(points).toStringAsFixed(2)} 公里',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  Text(
                    '起 ${points.first.at == null ? '--:--' : _hhmm(points.first.at!)}  '
                    '止 ${points.last.at == null ? '--:--' : _hhmm(points.last.at!)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: ref.read(trackDateProvider),
      firstDate: now.subtract(const Duration(days: 7)),
      // 不允许选未来：未来不可能有轨迹，选到只会得到空列表
      lastDate: now,
      helpText: '选择轨迹日期',
    );
    if (picked == null) {
      return;
    }
    _stop();
    setState(() => _index = 0);
    ref.read(trackDateProvider.notifier).select(picked);
  }

  // ------------------------------------------------------------------
  // 计算辅助
  // ------------------------------------------------------------------

  /// 根据当天轨迹的包围盒算出合适的缩放：让整条轨迹大致铺满画布。
  ///
  /// 用 1.25 的留白系数，避免首尾点正好贴边看不清。
  static double _metersPerPixel(List<TrackPoint> points, double width, double height) {
    if (points.length < 2 || width <= 0 || height <= 0) {
      return 0.6;
    }
    double minLng = points.first.lng, maxLng = points.first.lng;
    double minLat = points.first.lat, maxLat = points.first.lat;
    for (final p in points) {
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
    }
    final midLatRad = (minLat + maxLat) / 2 * math.pi / 180;
    // 经度方向每度的实际米数随纬度收缩，必须乘 cos(lat)，否则高纬度会明显偏大
    final spanX = (maxLng - minLng) * 111_320 * math.cos(midLatRad);
    final spanY = (maxLat - minLat) * 110_540;
    final usableWidth = width * 0.75;
    final usableHeight = height * 0.75;
    final mpp = math.max(spanX / usableWidth, spanY / usableHeight);
    // 夹到 0.5~200：太小会让轨迹抖动被放大成噪声，太大则点挤在一起分不清先后
    return mpp.clamp(0.5, 200.0);
  }

  static double _totalKm(List<TrackPoint> points) {
    double meters = 0;
    for (var i = 1; i < points.length; i++) {
      meters += _haversine(points[i - 1], points[i]);
    }
    return meters / 1000;
  }

  static double _haversine(TrackPoint a, TrackPoint b) {
    const r = 6371000.0;
    final dLat = (b.lat - a.lat) * math.pi / 180;
    final dLng = (b.lng - a.lng) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.lat * math.pi / 180) *
            math.cos(b.lat * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _hhmmss(DateTime t) =>
      '${_hhmm(t)}:${t.second.toString().padLeft(2, '0')}';
}
