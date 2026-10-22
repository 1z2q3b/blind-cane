import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_response.dart';
import '../../state/location_state.dart';
import '../../state/ward_state.dart';
import 'manual_location_sheet.dart';

/// 新建 / 编辑家人档案（提示词 5.2）。
class WardFormPage extends ConsumerStatefulWidget {
  const WardFormPage({super.key, this.wardId});

  /// 为 null 表示新建。
  final int? wardId;

  @override
  ConsumerState<WardFormPage> createState() => _WardFormPageState();
}

class _WardFormPageState extends ConsumerState<WardFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _relationCtrl = TextEditingController();
  final _birthYearCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  /// 家庭住址坐标（手动定位结果）。为 null 表示还没定位过。
  double? _homeLng;
  double? _homeLat;

  /// 手杖当前位置，作为手动定位的基准点。
  double? _deviceLng;
  double? _deviceLat;

  bool _loading = false;
  bool _prefilled = false;
  String? _error;

  bool get _isEdit => widget.wardId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _prefill();
    }
  }

  /// 编辑模式回填。只做一次，避免用户改到一半被刷新覆盖。
  Future<void> _prefill() async {
    try {
      final detail = await ref.read(wardDetailProvider(widget.wardId!).future);
      if (!mounted || _prefilled) {
        return;
      }
      _prefilled = true;
      _nameCtrl.text = detail.name;
      _relationCtrl.text = detail.relation ?? '';
      _birthYearCtrl.text = detail.birthYear?.toString() ?? '';
      _addressCtrl.text = detail.homeAddress ?? '';
      _phoneCtrl.text = detail.contactPhone ?? '';
      _notesCtrl.text = detail.medicalNotes ?? '';
      _homeLng = detail.homeLng;
      _homeLat = detail.homeLat;
      // 手杖当前位置作为手动定位的基准点：老人此刻多半就在家附近
      _deviceLng = detail.latestLocation?.lng;
      _deviceLat = detail.latestLocation?.lat;
      setState(() {});
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _relationCtrl.dispose();
    _birthYearCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  /// 打开手动定位面板。
  ///
  /// 新建档案时还没有 detail，手杖位置从实时位置 provider 取；
  /// 编辑时用详情里带回来的位置，避免多打一次接口。
  Future<void> _openManualLocation() async {
    var deviceLng = _deviceLng;
    var deviceLat = _deviceLat;
    if (deviceLng == null || deviceLat == null) {
      final latest = ref.read(locationProvider).latest;
      deviceLng = latest?.lng;
      deviceLat = latest?.lat;
    }
    final picked = await showModalBottomSheet<PickedLocation>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ManualLocationSheet(
        initialLng: _homeLng,
        initialLat: _homeLat,
        deviceLng: deviceLng,
        deviceLat: deviceLat,
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _homeLng = picked.lng;
      _homeLat = picked.lat;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    final notifier = ref.read(wardListProvider.notifier);

    final birthYear = int.tryParse(_birthYearCtrl.text.trim());
    try {
      if (_isEdit) {
        await notifier.updateWard(
          wardId: widget.wardId!,
          name: _nameCtrl.text.trim(),
          relation: _relationCtrl.text.trim(),
          birthYear: birthYear,
          homeAddress: _addressCtrl.text.trim(),
          homeLng: _homeLng,
          homeLat: _homeLat,
          contactPhone: _phoneCtrl.text.trim(),
          medicalNotes: _notesCtrl.text.trim(),
        );
        ref.invalidate(wardDetailProvider(widget.wardId!));
        messenger.showSnackBar(const SnackBar(content: Text('已保存')));
      } else {
        final created = await notifier.create(
          name: _nameCtrl.text.trim(),
          relation: _relationCtrl.text.trim(),
          birthYear: birthYear,
          homeAddress: _addressCtrl.text.trim(),
          homeLng: _homeLng,
          homeLat: _homeLat,
          contactPhone: _phoneCtrl.text.trim(),
          medicalNotes: _notesCtrl.text.trim(),
        );
        // 新建后自动选中该家人：家属建完档最想看到的就是"他的位置在哪"
        await ref.read(selectedWardIdProvider.notifier).select(created.id);
        messenger.showSnackBar(const SnackBar(content: Text('档案已创建')));
        // 用 pushReplacement 而不是 pop 再 push：
        // pop 之后当前 context 已经失效，紧接着再 push 会闪出一帧空栈，
        // 表现就是"刚建完档案，页面什么都没有"。pushReplacement 直接用详情页
        // 顶替表单页，返回时正好回到首页，栈层次也更干净。
        if (mounted) {
          router.pushReplacement('/wards/${created.id}');
        }
        return;
      }
      if (mounted) {
        navigator.pop();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '保存失败：$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_isEdit ? '编辑家人档案' : '添加家人'),
            // 构建标识直接放在这个页面的标题下方：这里正是「添加家人空白」
            // 反馈的现场。用户看到空白时，低头看一眼标题下面有没有这行小字，
            // 就知道自己跑的是新包还是 Service Worker 缓存里的旧包——
            // 没有这行字 = 旧包，硬刷新一次即可。
            Text(
              '构建 ${AppConfig.buildStamp}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '姓名 *',
                hintText: '如：张老先生',
                prefixIcon: Icon(Icons.person_outline),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) {
                  return '请填写姓名';
                }
                if (text.length > 20) {
                  return '姓名不超过 20 个字';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _relationCtrl,
              decoration: const InputDecoration(
                labelText: '与我的关系',
                hintText: '如：父亲 / 母亲 / 爷爷',
                prefixIcon: Icon(Icons.family_restroom),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _birthYearCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: '出生年份',
                hintText: '如：1952',
                prefixIcon: Icon(Icons.cake_outlined),
                counterText: '',
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) {
                  return null;
                }
                final year = int.tryParse(text);
                final now = DateTime.now().year;
                if (year == null || year < 1900 || year > now) {
                  return '请输入 1900 ~ $now 之间的年份';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-() ]')),
              ],
              decoration: const InputDecoration(
                labelText: '随身电话',
                hintText: '告警时一键拨打这个号码',
                prefixIcon: Icon(Icons.phone_in_talk_outlined),
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) {
                  return null;
                }
                // 只挡明显错误（含字母、过短），不硬卡 11 位——老人可能只有座机
                if (text.replaceAll(RegExp(r'[^0-9]'), '').length < 5) {
                  return '号码太短，请检查';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _addressCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '家庭住址',
                hintText: '用于离家/到家判断与反向定位',
                prefixIcon: Icon(Icons.home_outlined),
              ),
            ),
            const SizedBox(height: 10),
            _LocationStatusCard(
              lng: _homeLng,
              lat: _homeLat,
              onTap: _openManualLocation,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '病史与用药备注',
                hintText: '如：高血压，早 7 点服降压药；2024 年跌倒过一次右腿',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.medical_information_outlined),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.lock_outline,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '病史属于敏感信息，后端以 AES-256-GCM 加密存储，'
                    '仅本人与主监护人可查看。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style:
                            TextStyle(color: theme.colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
            // 全宽 CTA：主题 minimumSize 宽度为 0，全宽靠 SizedBox 撑
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_isEdit ? '保存修改' : '创建档案'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 住址坐标状态卡。
///
/// 单独做成一张卡而不是塞进输入框的 suffixIcon：
/// 「有没有定位过」是需要一眼看出来的状态，塞在输入框角上会被忽略；
/// 而围栏和离家判断都依赖这个坐标，漏配的代价是围栏默认中心兜不住。
class _LocationStatusCard extends StatelessWidget {
  const _LocationStatusCard({
    required this.lng,
    required this.lat,
    required this.onTap,
  });

  final double? lng;
  final double? lat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final located = lng != null && lat != null;
    final accent = located ? theme.colorScheme.primary : theme.colorScheme.outline;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(located ? Icons.place : Icons.place_outlined, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  located ? '住址已定位' : '住址未定位',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  located
                      ? '${lng!.toStringAsFixed(6)}, ${lat!.toStringAsFixed(6)}'
                      : '点「手动定位」确认家的位置，围栏和到家判断会用到它',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: onTap,
            icon: const Icon(Icons.gps_fixed, size: 18),
            label: Text(located ? '重新定位' : '手动定位'),
          ),
        ],
      ),
    );
  }
}
