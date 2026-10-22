import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/token_store.dart';
import '../models/alert.dart';
import 'providers.dart';
import 'ward_state.dart';

/// 告警列表筛选条件。
@immutable
class AlertFilter {
  const AlertFilter({this.wardId, this.type, this.status});

  /// null = 名下全部被监护人。
  final int? wardId;
  final String? type;

  /// 0 待处理 / 1 已处理 / 2 误报；null = 全部。
  final int? status;

  bool get isEmpty => wardId == null && type == null && status == null;

  AlertFilter copyWith({
    int? wardId,
    String? type,
    int? status,
    bool clearWardId = false,
    bool clearType = false,
    bool clearStatus = false,
  }) {
    return AlertFilter(
      wardId: clearWardId ? null : (wardId ?? this.wardId),
      type: clearType ? null : (type ?? this.type),
      status: clearStatus ? null : (status ?? this.status),
    );
  }
}

class AlertFilterNotifier extends Notifier<AlertFilter> {
  @override
  AlertFilter build() => const AlertFilter();

  void setWard(int? wardId) {
    state = wardId == null
        ? state.copyWith(clearWardId: true)
        : state.copyWith(wardId: wardId);
  }

  void setType(String? type) {
    state = type == null ? state.copyWith(clearType: true) : state.copyWith(type: type);
  }

  void setStatus(int? status) {
    state =
        status == null ? state.copyWith(clearStatus: true) : state.copyWith(status: status);
  }

  void reset() => state = const AlertFilter();
}

final alertFilterProvider =
    NotifierProvider<AlertFilterNotifier, AlertFilter>(AlertFilterNotifier.new);

@immutable
class AlertListState {
  const AlertListState({
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.loadingMore = false,
  });

  final List<AlertRecord> items;
  final int total;
  final int page;
  final bool loadingMore;

  bool get hasMore => items.length < total;

  AlertListState copyWith({
    List<AlertRecord>? items,
    int? total,
    int? page,
    bool? loadingMore,
  }) {
    return AlertListState(
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      loadingMore: loadingMore ?? this.loadingMore,
    );
  }
}

/// 告警历史列表（分页 + 筛选）。
class AlertListNotifier extends AsyncNotifier<AlertListState> {
  static const _pageSize = 20;

  @override
  Future<AlertListState> build() async {
    // 筛选条件一变就重新查第一页
    final filter = ref.watch(alertFilterProvider);
    final page = await ref.read(repositoryProvider).queryAlerts(
          wardId: filter.wardId,
          type: filter.type,
          status: filter.status,
          page: 1,
          size: _pageSize,
        );
    return AlertListState(items: page.records, total: page.total, page: 1);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) {
      return;
    }
    state = AsyncValue.data(current.copyWith(loadingMore: true));
    final filter = ref.read(alertFilterProvider);
    try {
      final page = await ref.read(repositoryProvider).queryAlerts(
            wardId: filter.wardId,
            type: filter.type,
            status: filter.status,
            page: current.page + 1,
            size: _pageSize,
          );
      final merged = [...current.items, ...page.records];
      state = AsyncValue.data(AlertListState(
        items: merged,
        total: page.total,
        page: current.page + 1,
      ));
    } catch (e, st) {
      // 加载更多失败保留已有数据，只把 loadingMore 复位
      state = AsyncValue.data(current.copyWith(loadingMore: false));
      debugPrint('[AlertList] 加载更多失败: $e\n$st');
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// 把 WebSocket 推送来的告警插到列表头部。
  ///
  /// 只在「没有筛选条件，或筛选条件与该告警匹配」时插入：
  /// 用户正在看「已处理」列表，却突然冒出一条待处理告警，会让人误以为筛选失效了。
  void prependFromPush(AlertRecord alert) {
    final current = state.value;
    if (current == null) {
      return;
    }
    if (current.items.any((e) => e.id == alert.id)) {
      // 跌倒升级会推两次同 id 的告警，去重后原地替换
      final replaced = current.items
          .map((e) => e.id == alert.id ? alert : e)
          .toList(growable: false);
      state = AsyncValue.data(current.copyWith(items: replaced));
      return;
    }
    final filter = ref.read(alertFilterProvider);
    if (filter.wardId != null && filter.wardId != alert.wardId) {
      return;
    }
    if (filter.type != null && filter.type != alert.alertType) {
      return;
    }
    if (filter.status != null && filter.status != alert.status) {
      return;
    }
    state = AsyncValue.data(current.copyWith(
      items: [alert, ...current.items],
      total: current.total + 1,
    ));
  }

  /// 处理告警后原地更新一条，避免整页重新加载导致滚动位置丢失。
  void replace(AlertRecord alert) {
    final current = state.value;
    if (current == null) {
      return;
    }
    final replaced = current.items
        .map((e) => e.id == alert.id ? alert : e)
        .toList(growable: false);
    state = AsyncValue.data(current.copyWith(items: replaced));
  }
}

final alertListProvider =
    AsyncNotifierProvider<AlertListNotifier, AlertListState>(AlertListNotifier.new);

/// 待处理告警数量（首页与底部导航角标共用）。
class PendingCountNotifier extends AsyncNotifier<PendingCount> {
  @override
  Future<PendingCount> build() async {
    return ref.read(repositoryProvider).pendingCount();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(repositoryProvider).pendingCount());
  }

  /// 收到新告警推送时本地自增，不用再打一次接口。
  void increase(int wardId) {
    final current = state.value;
    if (current == null) {
      refresh();
      return;
    }
    final byWard = Map<int, int>.from(current.byWard);
    byWard[wardId] = (byWard[wardId] ?? 0) + 1;
    state = AsyncValue.data(PendingCount(total: current.total + 1, byWard: byWard));
  }

  /// 告警被处理后本地自减。
  void decrease(int wardId) {
    final current = state.value;
    if (current == null || current.total <= 0) {
      return;
    }
    final byWard = Map<int, int>.from(current.byWard);
    final next = (byWard[wardId] ?? 0) - 1;
    if (next <= 0) {
      byWard.remove(wardId);
    } else {
      byWard[wardId] = next;
    }
    state = AsyncValue.data(
      PendingCount(total: current.total - 1, byWard: byWard),
    );
  }
}

final pendingCountProvider =
    AsyncNotifierProvider<PendingCountNotifier, PendingCount>(PendingCountNotifier.new);

/// 需要全屏强提醒的告警。
///
/// 只有 `severity == 1 且未处理` 的告警才会进来（见 `AlertRecord.requiresFullScreen`）。
class FullScreenAlertNotifier extends Notifier<AlertRecord?> {
  @override
  AlertRecord? build() => null;

  void push(AlertRecord alert) {
    // 通知开关关闭时不弹全屏——家属主动关掉通知的意愿要被尊重，
    // 但告警仍然会进列表和角标，不会丢。
    if (!ref.read(tokenStoreProvider).notifyEnabled) {
      return;
    }
    if (!alert.requiresFullScreen) {
      return;
    }
    state = alert;
  }

  /// 全屏页关闭。已经在展示的那条如果被处理了也要清掉，
  /// 否则会残留一张"已经处理过"的红屏。
  void dismiss() => state = null;

  void dismissIf(int alertId) {
    if (state?.id == alertId) {
      state = null;
    }
  }
}

final fullScreenAlertProvider =
    NotifierProvider<FullScreenAlertNotifier, AlertRecord?>(
        FullScreenAlertNotifier.new);

/// 首页「最近告警」需要的当前被监护人待处理数量。
final currentWardPendingCountProvider = Provider<int>((ref) {
  final wardId = ref.watch(selectedWardIdProvider);
  final pending = ref.watch(pendingCountProvider).asData?.value;
  if (wardId == null || pending == null) {
    return 0;
  }
  return pending.countOf(wardId);
});
