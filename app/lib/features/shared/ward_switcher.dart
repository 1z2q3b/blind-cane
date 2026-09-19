import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/ward_state.dart';

/// 被监护人切换器。
///
/// 只有一个被监护人时**不显示下拉箭头**，直接展示姓名：
/// 单人多一个能点开却只有一项的菜单，只会让人怀疑自己点错了。
class WardSwitcher extends ConsumerWidget {
  const WardSwitcher({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wards = ref.watch(wardListProvider);
    final current = ref.watch(currentWardProvider);
    final theme = Theme.of(context);

    return wards.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => Text('加载失败', style: TextStyle(color: theme.colorScheme.error)),
      data: (list) {
        if (list.isEmpty) {
          return TextButton.icon(
            onPressed: () => context.push('/wards/new'),
            icon: const Icon(Icons.add),
            label: const Text('添加家人'),
          );
        }
        final label = current?.name ?? list.first.name;
        if (list.length == 1) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: compact ? 17 : 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }
        return PopupMenuButton<int>(
          tooltip: '切换家人',
          onSelected: (wardId) {
            // -1 是「添加家人」的哨兵值：PopupMenuButton 的 onSelected
            // 只回传一个值，用它比再开一个回调参数更省事
            if (wardId == -1) {
              context.push('/wards/new');
              return;
            }
            ref.read(selectedWardIdProvider.notifier).select(wardId);
          },
          itemBuilder: (context) => [
            for (final ward in list)
              PopupMenuItem<int>(
                value: ward.id,
                child: Row(
                  children: [
                    Icon(
                      ward.id == current?.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: ward.id == current?.id
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 10),
                    Text(ward.name, style: const TextStyle(fontSize: 16)),
                    if (ward.pendingAlertCount > 0) ...[
                      const SizedBox(width: 8),
                      _Dot(count: ward.pendingAlertCount),
                    ],
                  ],
                ),
              ),
            const PopupMenuDivider(),
            PopupMenuItem<int>(
              value: -1,
              child: Row(
                children: const [
                  Icon(Icons.add, size: 20),
                  SizedBox(width: 10),
                  Text('添加家人', style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: compact ? 17 : 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
