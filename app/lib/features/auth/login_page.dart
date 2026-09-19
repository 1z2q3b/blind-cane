import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_response.dart';
import '../../core/theme/app_theme.dart';
import '../../state/auth_state.dart';

/// 登录页：手机号 + 短信验证码（提示词 5.1）。
///
/// 首次登录的号码后端会自动注册，因此页面上没有「注册」入口——
/// 多一个入口只会让家属在"我到底该点哪个"上卡住。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _codeFocus = FocusNode();

  Timer? _timer;
  int _countdown = 0;
  String? _mockCode;
  bool _sending = false;

  @override
  void dispose() {
    _timer?.cancel();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  bool get _phoneValid =>
      RegExp(r'^1[3-9]\d{9}$').hasMatch(_phoneCtrl.text.trim());

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _countdown = AppConfig.smsCountdownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        timer.cancel();
      }
    });
  }

  Future<void> _sendCode() async {
    if (!_phoneValid || _sending || _countdown > 0) {
      return;
    }
    setState(() => _sending = true);
    try {
      final code = await ref
          .read(authProvider.notifier)
          .sendSmsCode(_phoneCtrl.text.trim());
      if (!mounted) {
        return;
      }
      _startCountdown();
      setState(() => _mockCode = code);
      _codeFocus.requestFocus();
      if (code != null) {
        // 演示模式下后端直接回传验证码，自动填上省掉口播报数字的尴尬
        _codeCtrl.text = code;
        _showTip('演示模式：验证码已自动填入 $code');
      } else {
        _showTip('验证码已发送，5 分钟内有效');
      }
    } on ApiException catch (e) {
      if (mounted) {
        _showTip(e.message, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    if (!_phoneValid) {
      _showTip('请输入正确的手机号', isError: true);
      return;
    }
    if (_codeCtrl.text.trim().length != 6) {
      _showTip('请输入 6 位验证码', isError: true);
      return;
    }
    await ref.read(authProvider.notifier).login(
          phone: _phoneCtrl.text.trim(),
          smsCode: _codeCtrl.text.trim(),
        );
    // 登录成功后由路由的 redirect 自动跳首页，这里不需要手动导航
  }

  void _showTip(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Icon(Icons.sensor_occupied,
                      size: 72, color: theme.colorScheme.primary),
                  const SizedBox(height: 20),
                  Text(
                    '导盲杖家属端',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '随时了解家人的位置与安全状态',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 36),

                  if (auth.sessionExpired) _SessionExpiredBanner(theme: theme),

                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    maxLength: 11,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 19, letterSpacing: 1.2),
                    decoration: const InputDecoration(
                      labelText: '手机号',
                      hintText: '请输入 11 位手机号',
                      prefixIcon: Icon(Icons.phone_iphone),
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _codeCtrl,
                          focusNode: _codeFocus,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          style: const TextStyle(fontSize: 19, letterSpacing: 3),
                          decoration: const InputDecoration(
                            labelText: '验证码',
                            hintText: '6 位数字',
                            prefixIcon: Icon(Icons.password),
                            counterText: '',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        // 宽度给足 132 并压掉默认的水平内边距：
                        // 「获取验证码」5 个全角字符按主题的 17sp 算已经 ~85px，
                        // 再叠加默认 padding 会在 124 宽里折成两行。
                        width: 132,
                        height: AppTheme.minTouchSize,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            textStyle: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                          onPressed: (!_phoneValid || _countdown > 0 || _sending)
                              ? null
                              : _sendCode,
                          child: _sending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(
                                  _countdown > 0 ? '${_countdown}s' : '获取验证码',
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.visible,
                                ),
                        ),
                      ),
                    ],
                  ),

                  if (_mockCode != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.science_outlined,
                            size: 16, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '演示模式：短信未真实下发，验证码固定为 $_mockCode',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  if (auth.error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      auth.error!,
                      style: TextStyle(color: theme.colorScheme.error, fontSize: 15),
                    ),
                  ],

                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: auth.loading ? null : _login,
                    child: auth.loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('登录 / 注册'),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '未注册的手机号将自动创建账号\n'
                    '当前后端：${AppConfig.apiBaseUrl}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionExpiredBanner extends StatelessWidget {
  const _SessionExpiredBanner({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '登录已过期，请重新登录',
              style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
