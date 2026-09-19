import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_response.dart';
import '../../core/theme/app_theme.dart';
import '../../models/alert.dart';
import '../../state/alert_state.dart';
import '../../state/providers.dart';
import '../location/location_map_canvas.dart';
import '../shared/widgets.dart';

/// 告警详情与处理（提示词 5.6）。
class AlertDetailPage extends ConsumerStatefulWidget {
  const AlertDetailPage({super.key, required this.alertId});

  final int alertId;

  @override
  ConsumerState<AlertDetailPage> createState() => _AlertDetailPageState();
}

class _AlertDetailPageState extends ConsumerState<AlertDetailPage> {
  AlertRecord? _alert;
  bool _loading = true;
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final alert = await ref.read(repositoryProvider).alertDetail(widget.alertId);
      if (!mounted) {
        return;
      }
      setState(() {
        _alert = alert;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// 处理告警。[result] = RESOLVED / FALSE_ALARM。
  Future<void> _handle(String result) async {
    final alert = _alert;
    if (alert == null || _submitting) {
      return;
    }
    if (result == 'FALSE_ALARM') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('标记为误报？'),
          content: const Text('误报会从待处理列表中移除，但记录仍会保留在历史里。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认误报'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
    }
    // showDialog 是一次 await，期间页面可能已经被 pop（例如令牌失效被踢回登录页），
    // 之后再碰 context 就会抛异常
    if (!mounted) {
      return;
    }

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await ref.read(repositoryProvider).handleAlert(
            alertId: alert.id,
            result: result,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _alert = updated;
        _submitting = false;
      });
      // 列表与角标就地更新，不再整页重拉：
      // 家属连续处理多条告警时，重拉会让列表跳动、回到顶部
      ref.read(alertListProvider.notifier).replace(updated);
      ref.read(pendingCountProvider.notifier).decrease(updated.wardId);
      ref.read(fullScreenAlertProvider.notifier).dismissIf(updated.id);
      messenger.showSnackBar(SnackBar(
        content: Text(result == 'RESOLVED' ? '已标记为处理完成' : '已标记为误报'),
      ));
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _submitting = false);
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  Future<void> _call(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await launchUrl(uri);
      if (!ok) {
        messenger.showSnackBar(
          SnackBar(content: Text('当前环境无法拨号，请手动拨打 $number')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('当前环境无法拨号，请手动拨打 $number')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alert = _alert;

    return Scaffold(
      appBar: AppBar(title: const Text('告警详情')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : alert == null
                  ? const EmptyState(icon: Icons.help_outline, title: '告警不存在')
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: [
                        _Header(alert: alert),
                        if (alert.hasLocation) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 180,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: LocationMapCanvas(
                                lng: alert.lng,
                                lat: alert.lat,
                                // 告警只存坐标不存精度，给一个合理的默认值，
                                // 否则地图上会连精度圈都画不出来
                                accuracyM: 25,
                                metersPerPixel: 0.5,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _DetailRows(alert: alert),
                        const SizedBox(height: 24),
                        if (alert.isPending) ...[
                          FilledButton.icon(
                            onPressed:
                                _submitting ? null : () => _handle('RESOLVED'),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('标记为已处理'),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed:
                                _submitting ? null : () => _handle('FALSE_ALARM'),
                            icon: const Icon(Icons.report_gmailerrorred_outlined),
                            label: const Text('标记为误报'),
                          ),
                          const SizedBox(height: 12),
                        ],
                        OutlinedButton.icon(
                          onPressed: () => _call(_phoneOf(alert)),
                          icon: const Icon(Icons.call),
                          label: Text('拨打 ${_phoneOf(alert)}'),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          alert.isPending
                              ? '处理后该告警会从待处理列表移除'
                              : '该告警已结束处理流程，如需修改请联系技术支持',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
    );
  }

  /// 紧急电话：先打 120，其余情况打主监护人。
  ///
  /// 真实产品应优先拨打被监护人本人（若设备支持通话），
  /// MVP 阶段设备是概念机，先给急救号码兜底。
  String _phoneOf(AlertRecord alert) => '120';
}

class _Header extends StatelessWidget {
  const _Header({required this.alert});

  final AlertRecord alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AppTheme.severityColor(alert.severity, theme.colorScheme);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconOf(alert.kind), color: color, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  alert.kind.label,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  alert.severityLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (alert.isAwaitingConfirm) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.timer_outlined, size: 18, color: AppTheme.warning),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '这是疑似事件，仍在等待杖体按键确认。超时未取消会自动升级为紧急告警。',
                    style: TextStyle(fontSize: 14, color: AppTheme.warning),
                  ),
                ),
              ],
            ),
          ],
        ],
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

class _DetailRows extends StatelessWidget {
  const _DetailRows({required this.alert});

  final AlertRecord alert;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final rows = <(String, String)>[
      ('被监护人', alert.wardName ?? '#${alert.wardId}'),
      ('告警类型', '${alert.kind.label}（${alert.alertType}）'),
      ('严重级别', alert.severityLabel),
      ('处理状态', alert.statusLabel),
      ('发生时间', alert.createdAt == null ? '—' : fmt.format(alert.createdAt!)),
      if (alert.address != null && alert.address!.isNotEmpty)
        ('位置', alert.address!),
      if (alert.hasLocation)
        ('坐标', '${alert.lat}, ${alert.lng}'),
      if (alert.note != null && alert.note!.isNotEmpty) ('备注', alert.note!),
      if (alert.handledAt != null)
        ('处理时间', fmt.format(alert.handledAt!)),
    ];

    return Card(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      rows[i].$1,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      rows[i].$2,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 地图画布只需要「中心点 + 精度」，因此这里不再做任何类型适配——
/// 直接把 lng/lat 传给 LocationMapCanvas 即可。
