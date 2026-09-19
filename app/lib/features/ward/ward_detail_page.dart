import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_response.dart';
import '../../models/ward.dart';
import '../../state/ward_state.dart';
import '../shared/widgets.dart';

/// 家人档案详情 + 设备绑定/解绑（提示词 5.2）。
class WardDetailPage extends ConsumerStatefulWidget {
  const WardDetailPage({super.key, required this.wardId});

  final int wardId;

  @override
  ConsumerState<WardDetailPage> createState() => _WardDetailPageState();
}

class _WardDetailPageState extends ConsumerState<WardDetailPage> {
  bool _busy = false;

  Future<void> _bindDevice() async {
    final controller = TextEditingController(text: 'BC-2024-DEMO01');
    final sn = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('绑定导盲杖'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '请输入设备背面的 SN 码。演示环境可直接使用下方预填的演示设备。',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: '设备 SN',
                hintText: 'BC-2024-DEMO01',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('绑定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (sn == null || sn.isEmpty) {
      return;
    }
    // 弹窗期间页面可能已被返回键关闭，之后再用 context 会抛异常
    if (!mounted) {
      return;
    }

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    // 错误色在 await 之前取好：await 之后再用 context 属于跨异步间隙访问，
    // 组件可能已经卸载
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await ref
          .read(wardListProvider.notifier)
          .bindDevice(deviceSn: sn, wardId: widget.wardId);
      ref.invalidate(wardDetailProvider(widget.wardId));
      messenger.showSnackBar(const SnackBar(content: Text('设备绑定成功')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('绑定失败：${e.message}'),
        backgroundColor: errorColor,
      ));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _unbindDevice(int deviceId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('解绑设备？'),
        content: const Text('解绑后将无法再接收该家人的位置与告警，历史记录会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认解绑'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await ref.read(wardListProvider.notifier).unbindDevice(deviceId);
      ref.invalidate(wardDetailProvider(widget.wardId));
      messenger.showSnackBar(const SnackBar(content: Text('设备已解绑')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('解绑失败：${e.message}'),
        backgroundColor: errorColor,
      ));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(wardDetailProvider(widget.wardId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('家人档案'),
        actions: [
          IconButton(
            tooltip: '编辑',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await context.push('/wards/${widget.wardId}/edit');
              ref.invalidate(wardDetailProvider(widget.wardId));
            },
          ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: '加载失败\n$e',
          onRetry: () => ref.invalidate(wardDetailProvider(widget.wardId)),
        ),
        data: (ward) => RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(wardDetailProvider(widget.wardId)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _ProfileCard(ward: ward),
              const SectionTitle(title: '设备'),
              _DeviceCard(
                ward: ward,
                busy: _busy,
                onBind: _bindDevice,
                onUnbind: _unbindDevice,
              ),
              const SectionTitle(title: '病史与用药备注'),
              _MedicalCard(notes: ward.medicalNotes),
              const SizedBox(height: 24),
              Text(
                '病史备注在后端以 AES-256-GCM 密文存储，'
                '列表接口不返回该字段，仅详情页按需解密下发。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.ward});

  final WardDetail ward;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    ward.name.isNotEmpty ? ward.name.substring(0, 1) : '?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ward.name,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (ward.relation != null) ward.relation!,
                          if (ward.age != null) '${ward.age} 岁',
                          ward.isPrimaryGuardian ? '主监护人' : '协作家属',
                        ].join(' · '),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _Row(
              icon: Icons.home_outlined,
              label: '家庭住址',
              value: ward.homeAddress?.isNotEmpty == true ? ward.homeAddress! : '未填写',
            ),
            const SizedBox(height: 12),
            _Row(
              icon: Icons.cake_outlined,
              label: '出生年份',
              value: ward.birthYear == null ? '未填写' : '${ward.birthYear} 年',
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 16))),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.ward,
    required this.busy,
    required this.onBind,
    required this.onUnbind,
  });

  final WardDetail ward;
  final bool busy;
  final VoidCallback onBind;
  final void Function(int deviceId) onUnbind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final device = ward.device;

    if (device == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.link_off, size: 40, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              const Text('尚未绑定导盲杖', style: TextStyle(fontSize: 17)),
              const SizedBox(height: 6),
              Text(
                '绑定后即可接收实时位置、跌倒与 SOS 告警',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: busy ? null : onBind,
                icon: const Icon(Icons.add_link),
                label: const Text('绑定设备'),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.sensors, color: theme.colorScheme.primary, size: 30),
            title: Text(device.name,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600)),
            subtitle: Text('SN ${device.deviceSn}'
                '${device.firmwareVersion != null ? ' · 固件 ${device.firmwareVersion}' : ''}'),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OnlineBadge(online: device.online, text: device.lastOnlineText),
                BatteryBadge(device: device),
                SignalBadge(level: device.signalLevel),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.link_off),
            title: const Text('解绑设备'),
            subtitle: const Text('更换导盲杖或暂时停用时使用'),
            trailing: const Icon(Icons.chevron_right),
            onTap: busy ? null : () => onUnbind(device.id),
          ),
        ],
      ),
    );
  }
}

class _MedicalCard extends StatelessWidget {
  const _MedicalCard({required this.notes});

  final String? notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.medical_information_outlined,
                color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                notes == null || notes!.isEmpty ? '未填写' : notes!,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: notes == null || notes!.isEmpty
                      ? theme.colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
