import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_response.dart';
import '../../core/theme/app_theme.dart';
import '../../state/auth_state.dart';

/// 登录方式：验证码 / 密码。
enum _LoginMethod { sms, password }

/// 页面模式：登录 / 注册。
enum _PageMode { login, register }

/// 登录 / 注册页。
///
/// 两种登录方式（验证码 / 密码）+ 显式注册（手机号 + 密码 + 验证码）。
/// 注册是独立模式而不是「登录时顺带注册」：密码登录要求账号必须有密码，
/// 混在一起会让「没设密码的号码也能进系统」，账号语义说不通。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _pwdConfirmCtrl = TextEditingController();
  final _codeFocus = FocusNode();
  final _pwdFocus = FocusNode();

  Timer? _timer;
  int _countdown = 0;
  String? _mockCode;
  bool _sending = false;
  _LoginMethod _method = _LoginMethod.sms;
  _PageMode _mode = _PageMode.login;
  bool _pwdVisible = false;

  @override
  void dispose() {
    _timer?.cancel();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _pwdCtrl.dispose();
    _pwdConfirmCtrl.dispose();
    _codeFocus.dispose();
    _pwdFocus.dispose();
    super.dispose();
  }

  bool get _phoneValid =>
      RegExp(r'^1[3-9]\d{9}$').hasMatch(_phoneCtrl.text.trim());

  /// 密码规则与后端一致：6-20 位字母或数字。前端先拦一道，
  /// 省掉一次往返；真正的裁决始终在后端。
  bool get _pwdValid =>
      RegExp(r'^[0-9A-Za-z]{6,20}$').hasMatch(_pwdCtrl.text);

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
        // 演示模式下后端随机生成验证码并随响应回传，自动填入省去口播报数字
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

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final phone = _phoneCtrl.text.trim();
    if (!_phoneValid) {
      _showTip('请输入正确的手机号', isError: true);
      return;
    }

    if (_mode == _PageMode.register) {
      if (!_pwdValid) {
        _showTip('密码须为 6-20 位字母或数字', isError: true);
        return;
      }
      if (_pwdCtrl.text != _pwdConfirmCtrl.text) {
        _showTip('两次输入的密码不一致', isError: true);
        return;
      }
      if (_codeCtrl.text.trim().length != 6) {
        _showTip('请输入 6 位验证码', isError: true);
        return;
      }
      await ref.read(authProvider.notifier).register(
            phone: phone,
            password: _pwdCtrl.text,
            smsCode: _codeCtrl.text.trim(),
          );
      // 成功后由路由的 redirect 自动跳首页
      return;
    }

    if (_method == _LoginMethod.password) {
      if (_pwdCtrl.text.isEmpty) {
        _showTip('请输入密码', isError: true);
        return;
      }
      await ref.read(authProvider.notifier).login(
            phone: phone,
            password: _pwdCtrl.text,
          );
      return;
    }

    if (_codeCtrl.text.trim().length != 6) {
      _showTip('请输入 6 位验证码', isError: true);
      return;
    }
    await ref.read(authProvider.notifier).login(
          phone: phone,
          smsCode: _codeCtrl.text.trim(),
        );
  }

  void _switchMode(_PageMode mode) {
    if (_mode == mode) {
      return;
    }
    setState(() {
      _mode = mode;
      _mockCode = null;
      _codeCtrl.clear();
    });
    ref.read(authProvider.notifier).clearError();
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
                  const SizedBox(height: 28),

                  if (auth.sessionExpired) _SessionExpiredBanner(theme: theme),

                  // 登录 / 注册 模式切换。用 SegmentedButton 而不是两个 Tab：
                  // 这里只有两页且都不需要滑动，分段控件更直白
                  SegmentedButton<_PageMode>(
                    segments: const [
                      ButtonSegment(
                          value: _PageMode.login,
                          label: Text('登录'),
                          icon: Icon(Icons.person_outline)),
                      ButtonSegment(
                          value: _PageMode.register,
                          label: Text('注册'),
                          icon: Icon(Icons.person_add_alt)),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => _switchMode(s.first),
                  ),
                  const SizedBox(height: 24),

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

                  if (_mode == _PageMode.login &&
                      _method == _LoginMethod.password)
                    _buildPasswordField(theme)
                  else
                    _buildCodeField(theme),

                  if (_mode == _PageMode.register) ...[
                    const SizedBox(height: 16),
                    _buildPasswordField(theme),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pwdConfirmCtrl,
                      obscureText: true,
                        style: const TextStyle(fontSize: 19),
                      decoration: const InputDecoration(
                        labelText: '确认密码',
                        hintText: '再输入一次密码',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ],

                  if (_mockCode != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.science_outlined,
                            size: 16, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '演示模式：短信未真实下发，验证码为 $_mockCode',
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
                  // 全宽 CTA：主题 minimumSize 宽度为 0，全宽靠 SizedBox 撑
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: auth.loading ? null : _submit,
                      child: auth.loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_mode == _PageMode.login ? '登录' : '注册'),
                    ),
                  ),

                  // 登录态下的辅助操作：切换登录方式；注册态下回到登录
                  if (_mode == _PageMode.login)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _method = _method == _LoginMethod.sms
                              ? _LoginMethod.password
                              : _LoginMethod.sms;
                          _mockCode = null;
                        });
                        ref.read(authProvider.notifier).clearError();
                      },
                      child: Text(_method == _LoginMethod.sms ? '用密码登录' : '用验证码登录'),
                    )
                  else
                    TextButton(
                      onPressed: () => _switchMode(_PageMode.login),
                      child: const Text('已有账号，去登录'),
                    ),

                  const SizedBox(height: 8),
                  Text(
                    _mode == _PageMode.login
                        ? '当前后端：${AppConfig.apiBaseUrl}\n构建 ${AppConfig.buildStamp}'
                        : '注册即表示同意家属监护端使用规范\n当前后端：${AppConfig.apiBaseUrl}\n构建 ${AppConfig.buildStamp}',
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

  /// 密码输入框（登录与注册共用）。注册态的确认密码是另一个独立输入框，
  /// 不复用此方法——两个框的标签、图标、校验语义都不同。
  Widget _buildPasswordField(ThemeData theme) {
    return TextField(
      controller: _pwdCtrl,
      focusNode: _pwdFocus,
      obscureText: !_pwdVisible,
      style: const TextStyle(fontSize: 19),
      decoration: InputDecoration(
        labelText: '密码',
        hintText: '6-20 位字母或数字',
        prefixIcon: const Icon(Icons.lock_outline),
        // 可见性切换是家属端高频操作（输错时第一反应是看输对了没），
        // 明眼用户不需要防窥，默认藏起只是防误触
        suffixIcon: IconButton(
          icon: Icon(_pwdVisible
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined),
          onPressed: () => setState(() => _pwdVisible = !_pwdVisible),
        ),
      ),
      onSubmitted: (_) => _submit(),
    );
  }

  /// 验证码输入框 + 获取验证码按钮（登录与注册共用）。
  Widget _buildCodeField(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _codeCtrl,
            focusNode: _codeFocus,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
