import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/storage/token_store.dart';
import '../../core/ws/ws_client.dart';
import '../../state/auth_state.dart';
import '../../state/providers.dart';
import '../../state/ward_state.dart';
import '../../state/ws_bridge.dart';
import '../shared/widgets.dart';

/// 我的：账号、通知偏好、后端信息、演示工具。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool get _notifyEnabled => ref.read(tokenStoreProvider).notifyEnabled;
  bool get _soundEnabled => ref.read(tokenStoreProvider).soundEnabled;

  Future<void> _setNotify(bool value) async {
    await ref.read(tokenStoreProvider).setNotifyEnabled(value);
    setState(() {});
  }

  Future<void> _setSound(bool value) async {
    await ref.read(tokenStoreProvider).setSoundEnabled(value);
    setState(() {});
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('退出后将不再接收该账号的告警推送。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    ref.read(wsClientProvider).disconnect();
    await ref.read(authProvider.notifier).logout();
  }

  Future<void> _resetDemo() async {
    final ward = ref.read(currentWardProvider);
    final sn = ward?.device?.deviceSn;
    final messenger = ScaffoldMessenger.of(context);
    if (sn == null) {
      messenger.showSnackBar(const SnackBar(content: Text('当前家人未绑定设备')));
      return;
    }
    try {
      await ref.read(repositoryProvider).mockResetDevice(sn);
      messenger.showSnackBar(
        SnackBar(content: Text('演示设备 $sn 已复位（电量回满、恢复在线）')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('复位失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);
    final wsStatus = ref.watch(wsStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      _initialOf(auth.user?.nickname ?? '家'),
                      style: TextStyle(
                        fontSize: 22,
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
                          auth.user?.nickname ?? '未登录',
                          style: const TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          auth.user?.maskedPhone ?? '',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SectionTitle(title: '通知'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: _notifyEnabled,
                  onChanged: _setNotify,
                  title: const Text('接收告警通知'),
                  subtitle: const Text('关闭后不弹全屏提醒，告警仍会进入列表'),
                  secondary: const Icon(Icons.notifications_active_outlined),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  value: _soundEnabled,
                  onChanged: _soundEnabled ? _setSound : null,
                  title: const Text('提示音与振动'),
                  subtitle: Text(
                    _notifyEnabled ? '紧急告警到达时发声并震动' : '需先开启告警通知',
                  ),
                  secondary: const Icon(Icons.volume_up_outlined),
                ),
              ],
            ),
          ),

          const SectionTitle(title: '连接状态'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    wsStatus == WsStatus.connected
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    color: wsStatus == WsStatus.connected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                  title: const Text('实时推送通道'),
                  subtitle: Text(_wsStatusText(wsStatus)),
                  trailing: TextButton(
                    onPressed: () {
                      final wardId = ref.read(selectedWardIdProvider);
                      if (wardId != null) {
                        ref.read(wsClientProvider).connect(wardId);
                      }
                    },
                    child: const Text('重连'),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('后端地址'),
                  subtitle: Text(
                    '${AppConfig.apiBaseUrl}\n${AppConfig.wsUrl}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),

          if (AppConfig.demoMode) ...[
            const SectionTitle(title: '演示工具'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.restart_alt),
                    title: const Text('复位演示设备'),
                    subtitle: const Text('电量回满、恢复在线，两次演示之间使用'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _resetDemo,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.sms_outlined),
                    title: const Text('重置短信发送次数'),
                    subtitle: const Text('清掉当日限流，便于反复演示登录'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final phone = auth.user?.phone;
                      final messenger = ScaffoldMessenger.of(context);
                      if (phone == null) {
                        return;
                      }
                      try {
                        await ref.read(repositoryProvider).mockResetSms(phone);
                        messenger.showSnackBar(
                          const SnackBar(content: Text('短信限流已重置')),
                        );
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('重置失败：$e')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],

          const SectionTitle(title: '关于'),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('版本'),
                  subtitle: Text('阶段一 MVP · 家属监护端'),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('数据来源'),
                  subtitle: Text(
                    AppConfig.demoMode
                        ? '设备数据由后端「设备模拟器」产出（无真实硬件）'
                        : '已连接真实设备',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error),
            ),
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('退出登录'),
          ),
          const SizedBox(height: 20),
          Text(
            '导盲杖家属端 MVP\n第二阶段将接入：高德底图、设备双向通话、围栏与轨迹回放',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 昵称首字符作头像文本。空串（后端可能默认 NULL）直接取'家'：
  /// 直接对空串调 substring 会抛 RangeError，整页红屏。
  String _initialOf(String? name) {
    final value = name?.trim() ?? '';
    return value.isEmpty ? '家' : value.substring(0, 1);
  }

  String _wsStatusText(WsStatus status) {
    return switch (status) {
      WsStatus.connected => '已连接，位置与告警实时推送',
      WsStatus.connecting => '连接中…',
      WsStatus.disconnected => '已断开，每 20 秒轮询兜底',
      WsStatus.idle => '未启动',
    };
  }
}
