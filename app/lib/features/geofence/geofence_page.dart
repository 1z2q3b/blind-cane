import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_response.dart';
import '../../core/theme/app_theme.dart';
import '../../models/geofence.dart';
import '../../state/geofence_state.dart';
import '../../state/location_state.dart';
import '../../state/ward_state.dart';

/// 电子围栏管理页。
///
/// <p>信息层次刻意做得扁平：家属在这个页面只关心三件事——有哪些围栏、
/// 是不是开着、要不要改。所以列表项上直接给「类型 + 规则 + 半径 + 开关」，
/// 不点进去也能判断，减少往返。
class GeofencePage extends ConsumerWidget {
  const GeofencePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(geofenceListProvider);
    final ward = ref.watch(currentWardProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(ward == null ? '电子围栏' : '${ward.name} · 电子围栏'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(geofenceListProvider.notifier).refresh(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('新建围栏'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(
          message: _humanize(error),
          onRetry: () => ref.read(geofenceListProvider.notifier).refresh(),
        ),
        data: (fences) {
          if (fences.isEmpty) {
            return const _EmptyView();
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(geofenceListProvider.notifier).refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: fences.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _FenceCard(
                fence: fences[index],
                onToggle: (enabled) =>
                    _toggle(context, ref, fences[index], enabled),
                onEdit: () => _openEditor(context, ref, editing: fences[index]),
                onDelete: () => _confirmDelete(context, ref, fences[index]),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggle(
      BuildContext context, WidgetRef ref, Geofence fence, bool enabled) async {
    try {
      await ref.read(geofenceListProvider.notifier).toggle(fence.id, enabled);
      if (!context.mounted) return;
      _toast(context, enabled ? '已启用「${fence.name}」' : '已停用「${fence.name}」');
    } on ApiException catch (e) {
      if (!context.mounted) return;
      _toast(context, e.message, error: true);
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Geofence fence) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除围栏'),
        content: Text('确定删除「${fence.name}」吗？删除后不再对它做越界判断。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.critical),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref.read(geofenceListProvider.notifier).remove(fence.id);
      if (!context.mounted) return;
      _toast(context, '已删除「${fence.name}」');
    } on ApiException catch (e) {
      if (!context.mounted) return;
      _toast(context, e.message, error: true);
    }
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref,
      {Geofence? editing}) async {
    final latest = ref.read(locationProvider).latest;
    if (editing == null && latest == null) {
      // 新建时中心点默认取当前位置：家属说不清经纬度，但"就在老人现在待的地方"
      // 是自然表达。没有定位数据就无法建围栏，这里直接拦下来并说明原因。
      _toast(context, '还没有收到手杖定位，暂时无法确定围栏中心点', error: true);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FenceEditor(
        editing: editing,
        fallbackLng: latest?.lng,
        fallbackLat: latest?.lat,
      ),
    );
  }

  void _toast(BuildContext context, String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? AppTheme.critical : null,
      ));
  }

  /// 把 ApiException 的文案提出来，其余异常给一句人话 + 原始信息
  /// 不要在界面上直接抛 stack trace，家属看不懂也没法处理。
  static String _humanize(Object error) {
    if (error is ApiException) {
      return error.message;
    }
    return '加载围栏失败：$error';
  }
}

class _FenceCard extends StatelessWidget {
  const _FenceCard({
    required this.fence,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final Geofence fence;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safe = fence.type == FenceType.safe;
    final accent = safe ? AppTheme.seed : AppTheme.warning;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  safe ? Icons.shield_outlined : Icons.warning_amber_rounded,
                  color: fence.isEnabled ? accent : theme.disabledColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    fence.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Switch(
                  value: fence.isEnabled,
                  onChanged: onToggle,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Chip(text: fence.type.label, color: accent),
                _Chip(text: fence.type.ruleLabel),
                _Chip(text: '半径 ${fence.radiusM} 米'),
                if (!fence.isEnabled) const _Chip(text: '已停用'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '中心 ${fence.centerLng.toStringAsFixed(5)}, '
              '${fence.centerLat.toStringAsFixed(5)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('编辑'),
                ),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('删除'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = color ?? theme.colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: base.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(color: base),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fence_outlined,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('还没有设置围栏', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '设置「安全区」后，家人走出这个范围会立刻收到提醒；\n'
              '设置「危险区」后，家人走进河边、工地等区域会收到提醒。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

/// 新建 / 编辑围栏的表单。
///
/// 中心点不给手输经纬度：家属不可能知道这些数字。新建时取当前位置作为中心，
/// 编辑时沿用原中心（只改名称、类型、半径）。想换位置的场景（搬家）直接删了重加。
class _FenceEditor extends ConsumerStatefulWidget {
  const _FenceEditor({this.editing, this.fallbackLng, this.fallbackLat});

  final Geofence? editing;
  final double? fallbackLng;
  final double? fallbackLat;

  @override
  ConsumerState<_FenceEditor> createState() => _FenceEditorState();
}

class _FenceEditorState extends ConsumerState<_FenceEditor> {
  late final TextEditingController _nameCtrl;
  late FenceType _type;
  late double _radius;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    _nameCtrl = TextEditingController(text: editing?.name ?? '');
    _type = FenceType.fromValue(editing?.fenceType);
    _radius = (editing?.radiusM ?? 500).toDouble();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.editing != null;
    final lng = widget.editing?.centerLng ?? widget.fallbackLng ?? 0;
    final lat = widget.editing?.centerLat ?? widget.fallbackLat ?? 0;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(isEdit ? '编辑围栏' : '新建围栏',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            maxLength: 50,
            decoration: const InputDecoration(
              labelText: '围栏名称',
              hintText: '例如：小区周边 / 河边',
              prefixIcon: Icon(Icons.label_outline),
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<FenceType>(
            segments: const [
              ButtonSegment(
                value: FenceType.safe,
                label: Text('安全区'),
                icon: Icon(Icons.shield_outlined),
              ),
              ButtonSegment(
                value: FenceType.danger,
                label: Text('危险区'),
                icon: Icon(Icons.warning_amber_rounded),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 8),
          Text(
            _type == FenceType.safe ? '家人离开这个范围时提醒你' : '家人进入这个范围时提醒你',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('半径', style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text('${_radius.round()} 米',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          Slider(
            value: _radius,
            min: 20,
            max: 5000,
            // 20 米起步时 1 米一档太密，滑一点跳几百米更符合实际调节习惯；
            // 分段用 10 米，保证能精确调到 100/500 这类整数。
            divisions: 498,
            label: '${_radius.round()} 米',
            onChanged: (v) => setState(() => _radius = v),
          ),
          Text(
            '中心点：${lng.toStringAsFixed(5)}, ${lat.toStringAsFixed(5)}'
            '${isEdit ? '' : '（当前位置）'}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          // 全宽 CTA：主题 minimumSize 宽度为 0，全宽靠 SizedBox 撑
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : () => _save(lng, lat),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(isEdit ? '保存' : '创建'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save(double lng, double lat) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast('请填写围栏名称');
      return;
    }
    setState(() => _saving = true);
    final notifier = ref.read(geofenceListProvider.notifier);
    try {
      final editing = widget.editing;
      if (editing == null) {
        await notifier.create(
          name: name,
          centerLng: lng,
          centerLat: lat,
          radiusM: _radius.round(),
          fenceType: _type.value,
        );
      } else {
        await notifier.edit(
          editing.id,
          name: name,
          radiusM: _radius.round(),
          fenceType: _type.value,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(e.message);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.critical,
      ));
  }
}
