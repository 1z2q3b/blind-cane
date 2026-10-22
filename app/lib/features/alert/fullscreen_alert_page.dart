import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_response.dart';
import '../../core/theme/app_theme.dart';
import '../../models/alert.dart';
import '../../state/alert_state.dart';
import '../../state/providers.dart';
import '../../state/ward_state.dart';
import '../../core/map/smart_map_view.dart';

/// 全屏强提醒页（提示词 5.8）。
///
/// 这是整个 App 里唯一一个「打断用户」的界面，因此克制地只在
/// severity=1 且未处理的告警上出现。设计上做了三件事：
/// 1. 整屏红色 + 最大字号，保证在任何光线和视力条件下都能看清；
/// 2. 三个动作按「紧急程度」从上到下排列：拨号 → 看位置 → 处理；
/// 3. 进入时震动一次（移动端），Web 上静默降级。
class FullScreenAlertPage extends ConsumerStatefulWidget {
  const FullScreenAlertPage({super.key, required this.alert});

  final AlertRecord alert;

  @override
  ConsumerState<FullScreenAlertPage> createState() => _FullScreenAlertPageState();
}

class _FullScreenAlertPageState extends ConsumerState<FullScreenAlertPage> {
  late AlertRecord _alert = widget.alert;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // 触觉反馈是「强制唤起注意」里成本最低的一环；
    // Web 与桌面端没有振动马达，HapticFeedback 会静默失败，不需要 try/catch
    HapticFeedback.heavyImpact();
    // 拉一次最新详情：推送到达时该告警可能已经被其他家属处理了，
    // 直接展示推送里的旧快照会出现「别人已处理，你还在被要求处理」
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final latest = await ref.read(repositoryProvider).alertDetail(_alert.id);
      if (mounted) {
        setState(() => _alert = latest);
      }
    } on ApiException {
      // 刷新失败无所谓：已有推送快照足以展示，不打断家属
    }
  }

  Future<void> _handle(String result) async {
    if (_submitting) {
      return;
    }
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final updated = await ref.read(repositoryProvider).handleAlert(
            alertId: _alert.id,
            result: result,
          );
      ref.read(alertListProvider.notifier).replace(updated);
      ref.read(pendingCountProvider.notifier).decrease(updated.wardId);
      ref.read(fullScreenAlertProvider.notifier).dismissIf(updated.id);
      if (mounted) {
        navigator.pop();
      }
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

  /// 紧急拨打目标：优先被监护人随身电话，没填才退回急救号码。
  ///
  /// 全屏告警是"最急的那一下"，拨错对象的代价很高——直接打给老人本人
  /// 才能第一时间确认他是否清醒、是否需要叫救护车。
  String _callTarget() {
    final wards = ref.watch(wardListProvider).asData?.value;
    if (wards != null) {
      for (final ward in wards) {
        if (ward.id != _alert.wardId) {
          continue;
        }
        final phone = ward.contactPhone?.trim();
        if (phone != null && phone.isNotEmpty) {
          return phone;
        }
      }
    }
    return AppConfig.emergencyNumber;
  }

  Future<void> _call(String number) async {
    try {
      await launchUrl(Uri(scheme: 'tel', path: number));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('当前环境无法拨号，请手动拨打 $number')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('HH:mm:ss');
    final theme = Theme.of(context);

    return PopScope(
      // 允许返回：家属可能想先看别处再回来处理。
      // 强制"必须处理才能关闭"会让人焦虑，而且真有紧急情况时
      // 家属更可能先去打电话，而不是在 App 里点按钮。
      canPop: true,
      child: Scaffold(
        backgroundColor: AppTheme.critical,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            minimumSize: const Size(52, 52),
                          ),
                          icon: const Icon(Icons.close, color: Colors.white),
                          label: const Text(
                            '稍后处理',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          width: 104,
                          height: 104,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.warning_amber_rounded,
                              size: 64, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _alert.kind.label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _alert.wardName?.isNotEmpty == true
                            ? _alert.wardName!
                            : '家人',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _alert.createdAt == null
                            ? ''
                            : '触发时间 ${fmt.format(_alert.createdAt!)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 16,
                        ),
                      ),
                      if (_alert.isAwaitingConfirm) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            '疑似事件，仍在确认窗口中。若为误报可按「误报」取消；超时未处理将自动升级。',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 15),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      if (_alert.hasLocation)
                        Container(
                          height: 200,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              Expanded(
                                child: SmartMapView(
                                  lng: _alert.lng,
                                  lat: _alert.lat,
                                  accuracyM: 25,
                                  metersPerPixel: 0.5,
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 0, 12, 10),
                                child: Row(
                                  children: [
                                    const Icon(Icons.place,
                                        size: 16, color: AppTheme.critical),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _alert.address?.isNotEmpty == true
                                            ? _alert.address!
                                            : '${_alert.lat}, ${_alert.lng}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_alert.note != null && _alert.note!.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          _alert.note!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.95),
                            fontSize: 15,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      // 这三个按钮要全宽：父级 Column 不是 stretch，
                      // 用 SizedBox 撑满（主题 minimumSize 宽度已改为 0，
                      // 不能再靠 Size.fromHeight 的 ∞ 宽）。
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppTheme.critical,
                            minimumSize: const Size(0, 62),
                            textStyle: const TextStyle(
                                fontSize: 21, fontWeight: FontWeight.w700),
                          ),
                          onPressed: () => _call(_callTarget()),
                          icon: const Icon(Icons.call, size: 26),
                          label: Text('立即拨打 ${_callTarget()}'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white, width: 1.6),
                            minimumSize: const Size(0, 56),
                          ),
                          onPressed: () => _handle('RESOLVED'),
                          icon: const Icon(Icons.check_circle_outline, size: 24),
                          label: const Text('我已确认，标记已处理',
                              style: TextStyle(fontSize: 18)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed:
                              _submitting ? null : () => _handle('FALSE_ALARM'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white.withValues(alpha: 0.9),
                            minimumSize: const Size(0, 52),
                          ),
                          child: const Text('这是误报', style: TextStyle(fontSize: 17)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '提示：当前通话号码为 ${AppConfig.emergencyNumber}（急救）。'
                        '二期接入设备双向通话后，此处将改为直连导盲杖。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _alert.isPending ? '' : '该告警已被处理',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.colorScheme.surface,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
