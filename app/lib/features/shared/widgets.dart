import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/device_info.dart';

/// 在线/离线徽章。
class OnlineBadge extends StatelessWidget {
  const OnlineBadge({super.key, required this.online, this.text});

  final bool online;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final color = online ? AppTheme.healthy : Theme.of(context).colorScheme.outline;
    return _Pill(
      color: color,
      icon: online ? Icons.wifi_tethering : Icons.wifi_off,
      text: text ?? (online ? '在线' : '离线'),
    );
  }
}

/// 电量徽章：低于 20% 变橙、低于 10% 变红，保证一眼能看出异常。
class BatteryBadge extends StatelessWidget {
  const BatteryBadge({super.key, required this.device});

  final DeviceInfo? device;

  @override
  Widget build(BuildContext context) {
    final battery = device?.battery;
    if (battery == null) {
      return const _Pill(
        color: Colors.grey,
        icon: Icons.battery_unknown,
        text: '--',
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final color = switch (device!.batteryLevel) {
      BatteryLevel.critical => AppTheme.critical,
      BatteryLevel.low => AppTheme.warning,
      BatteryLevel.normal => scheme.primary,
    };
    final icon = switch (device!.batteryLevel) {
      BatteryLevel.critical => Icons.battery_alert,
      BatteryLevel.low => Icons.battery_3_bar,
      BatteryLevel.normal => Icons.battery_full,
    };
    return _Pill(color: color, icon: icon, text: '$battery%');
  }
}

/// 信号强度徽章（1~4 格）。
class SignalBadge extends StatelessWidget {
  const SignalBadge({super.key, this.level});

  final int? level;

  @override
  Widget build(BuildContext context) {
    final value = level ?? 0;
    final icon = value >= 3
        ? Icons.signal_cellular_alt
        : value >= 1
            ? Icons.signal_cellular_alt_2_bar
            : Icons.signal_cellular_off;
    return _Pill(
      color: value >= 1
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.outline,
      icon: icon,
      text: value >= 1 ? '信号 $value' : '无信号',
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.icon, required this.text});

  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 统一的空状态。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              // 空态 CTA 全宽：主题 minimumSize 宽度为 0，全宽靠 SizedBox 撑
              SizedBox(width: double.infinity, child: action!),
            ],
          ],
        ),
      ),
    );
  }
}

/// 统一的错误 + 重试。
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off,
                size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              // 全宽 CTA：主题 minimumSize 宽度为 0，全宽靠 SizedBox 撑
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 区块标题。
class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          ?action,
        ],
      ),
    );
  }
}
