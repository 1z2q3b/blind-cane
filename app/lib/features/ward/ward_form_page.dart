import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_response.dart';
import '../../state/ward_state.dart';

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
  final _notesCtrl = TextEditingController();

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
      _notesCtrl.text = detail.medicalNotes ?? '';
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
    _notesCtrl.dispose();
    super.dispose();
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
          medicalNotes: _notesCtrl.text.trim(),
        );
        // 新建后自动选中该家人：家属建完档最想看到的就是"他的位置在哪"
        await ref.read(selectedWardIdProvider.notifier).select(created.id);
        messenger.showSnackBar(const SnackBar(content: Text('档案已创建')));
        if (mounted) {
          navigator.pop();
          router.push('/wards/${created.id}');
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
      appBar: AppBar(title: Text(_isEdit ? '编辑家人档案' : '添加家人')),
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
              controller: _addressCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '家庭住址',
                hintText: '用于离家/到家判断与反向定位',
                prefixIcon: Icon(Icons.home_outlined),
              ),
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
            FilledButton(
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
          ],
        ),
      ),
    );
  }
}
