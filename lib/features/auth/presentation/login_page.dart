import 'dart:async';

import 'package:flutter/material.dart';
import 'package:review/core/design_system/components/review_frosted_app_bar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/utils/app_dialog.dart';
import '../../../core/utils/app_toast.dart';
import '../../feed/presentation/feed_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  static const MethodChannel _authChannel = MethodChannel(
    'com.review/weibo_auth',
  );

  final _areaController = TextEditingController(text: '86');
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  Timer? _countdownTimer;
  String? _challengeNumber;
  String? _challengePhone;
  String? _challengeArea;
  int _countdown = 0;
  bool _isRequestingCode = false;
  bool _isLoggingIn = false;
  bool _passwordMode = false;
  bool _passwordVisible = false;
  bool _hasPendingNativeSession = false;

  String get _area => _areaController.text.replaceAll(RegExp(r'\D'), '');
  String get _phone => _phoneController.text.replaceAll(RegExp(r'\D'), '');
  String get _smsCode => _codeController.text.replaceAll(RegExp(r'\D'), '');

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_handleChallengeInputChange);
    _areaController.addListener(_handleChallengeInputChange);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _phoneController.removeListener(_handleChallengeInputChange);
    _areaController.removeListener(_handleChallengeInputChange);
    _areaController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleChallengeInputChange() {
    if (_challengePhone == null ||
        (_challengePhone == _phone && _challengeArea == _area)) {
      return;
    }
    _countdownTimer?.cancel();
    setState(() {
      _challengeNumber = null;
      _challengePhone = null;
      _challengeArea = null;
      _countdown = 0;
      _codeController.clear();
    });
  }

  void _showMessage(String message) {
    if (mounted) AppToast.show(context, message);
  }

  void _switchLoginMode(bool passwordMode) {
    if (_passwordMode == passwordMode) return;
    _countdownTimer?.cancel();
    setState(() {
      _passwordMode = passwordMode;
      _challengeNumber = null;
      _challengePhone = null;
      _challengeArea = null;
      _countdown = 0;
      _codeController.clear();
      _passwordController.clear();
      _passwordVisible = false;
    });
  }

  Future<void> _requestSmsCode() async {
    if (_phone.length < 5 || _area.isEmpty) {
      _showMessage('请输入国家区号和手机号');
      return;
    }

    setState(() => _isRequestingCode = true);
    try {
      final response = await _authChannel.invokeMapMethod<String, dynamic>(
        'requestSmsCode',
        {'phone': _phone, 'area': _area},
      );
      final number = response?['number']?.toString() ?? '';
      if (response?['sent'] != true || number.isEmpty) {
        throw PlatformException(
          code: 'SMS_NOT_SENT',
          message: '微博没有返回验证码校验信息，请稍后重试',
        );
      }
      if (!mounted) return;
      _challengeNumber = number;
      _challengePhone = _phone;
      _challengeArea = _area;
      _codeController.clear();
      _countdown = 60;
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          if (_countdown <= 1) {
            _countdown = 0;
            timer.cancel();
          } else {
            _countdown--;
          }
        });
      });
      if (mounted) setState(() {});
      _showMessage('验证码已发送');
    } on PlatformException catch (error) {
      _showMessage(error.message ?? '验证码发送失败，请稍后重试');
    } catch (_) {
      _showMessage('验证码发送失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _isRequestingCode = false);
    }
  }

  Future<void> _loginWithSms() async {
    if (_phone.length < 5 || _area.isEmpty) {
      _showMessage('请输入国家区号和手机号');
      return;
    }
    if (_challengeNumber == null ||
        _challengePhone != _phone ||
        _challengeArea != _area) {
      _showMessage('请先获取当前手机号的验证码');
      return;
    }
    if (_smsCode.length < 4) {
      _showMessage('请输入短信验证码');
      return;
    }

    setState(() => _isLoggingIn = true);
    try {
      final response = await _authChannel.invokeMapMethod<String, dynamic>(
        'loginWithSms',
        {
          'phone': _phone,
          'area': _area,
          'number': _challengeNumber,
          'smsCode': _smsCode,
        },
      );
      await _completeNativeLogin(response);
    } on PlatformException catch (error) {
      _showMessage(error.message ?? '短信登录失败，请重试');
    } catch (_) {
      _showMessage('登录失败，请检查网络和验证码后重试');
    } finally {
      if (_hasPendingNativeSession) {
        try {
          await _authChannel.invokeMethod('discardPendingSession');
        } catch (_) {}
        _hasPendingNativeSession = false;
      }
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  Future<void> _loginWithPassword() async {
    final account = _accountController.text.trim();
    final password = _passwordController.text;
    if (account.isEmpty || password.isEmpty) {
      _showMessage('请输入微博账号和密码');
      return;
    }
    if (account.length > 128 || password.length > 256) {
      _showMessage('账号或密码长度无效');
      return;
    }

    setState(() => _isLoggingIn = true);
    _passwordController.clear();
    try {
      final response = await _authChannel.invokeMapMethod<String, dynamic>(
        'loginWithPassword',
        {'account': account, 'password': password},
      );
      await _completeNativeLogin(response);
    } on PlatformException catch (error) {
      _showMessage(error.message ?? '账号密码登录失败，请重试');
    } catch (_) {
      _showMessage('登录失败，请检查网络和账号信息后重试');
    } finally {
      if (_hasPendingNativeSession) {
        try {
          await _authChannel.invokeMethod('discardPendingSession');
        } catch (_) {}
        _hasPendingNativeSession = false;
      }
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  Future<void> _completeNativeLogin(Map<String, dynamic>? response) async {
    _hasPendingNativeSession = true;
    if (!mounted) return;
    final cookie = response?['cookie']?.toString() ?? '';
    if (cookie.isEmpty) {
      throw PlatformException(
        code: 'SESSION_COOKIE_MISSING',
        message: '微博未返回可供 Review 验证的登录凭据',
      );
    }

    final authNotifier = ref.read(authProvider.notifier);
    final verified = await authNotifier.setAndVerifyCookie(
      cookie,
      requireDesktopSession: false,
    );
    if (!verified) {
      throw PlatformException(
        code: 'SESSION_NOT_VERIFIED',
        message: '微博已返回登录凭据，但 Review 暂时无法验证该会话',
      );
    }

    final saved =
        await _authChannel.invokeMethod<bool>('acceptSession') ?? false;
    if (!saved) {
      await authNotifier.logout();
      throw PlatformException(
        code: 'SESSION_SAVE_FAILED',
        message: '加密保存登录会话失败，请重试',
      );
    }
    _hasPendingNativeSession = false;
    await authNotifier.reconcileNativeSession();
    ref.read(feedControllerProvider.notifier).setCategory('friends');
    if (mounted) {
      AppToast.show(context, '登录成功，已切换至关注流');
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _showCookieImportDialog() async {
    final controller = TextEditingController();
    await showAppDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导入 Cookie'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '粘贴微博 Cookie，或单独粘贴 SUB。',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'SUB=...; SUBP=...',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final raw = controller.text.trim();
              if (raw.isEmpty) return;
              Navigator.pop(dialogContext);
              final success = await ref
                  .read(authProvider.notifier)
                  .setAndVerifyCookie(raw);
              if (!success) {
                _showMessage('导入失败，未识别到有效 Cookie');
                return;
              }
              try {
                await _authChannel.invokeMethod('logout');
              } catch (_) {}
              ref.read(feedControllerProvider.notifier).setCategory('friends');
              if (mounted) {
                AppToast.show(context, 'Cookie 导入成功，已切换至关注流');
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('验证并导入'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final busy = _isRequestingCode || _isLoggingIn;

    return Scaffold(
      appBar: ReviewFrostedAppBar(
        title: const Text('账号登录'),
        actions: [
          TextButton(
            onPressed: busy ? null : _showCookieImportDialog,
            child: const Text('Cookie 导入'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 36, 32, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_passwordMode) ...[
                    TextField(
                      controller: _accountController,
                      enabled: !busy,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [
                        AutofillHints.username,
                        AutofillHints.email,
                      ],
                      decoration: const InputDecoration(
                        hintText: '手机号、邮箱或微博账号',
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordController,
                      enabled: !busy,
                      obscureText: !_passwordVisible,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _loginWithPassword(),
                      decoration: InputDecoration(
                        hintText: '登录密码',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _passwordVisible = !_passwordVisible,
                          ),
                          tooltip: _passwordVisible ? '隐藏密码' : '显示密码',
                          icon: Icon(
                            _passwordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 56,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                        ),
                        onPressed: busy ? null : _loginWithPassword,
                        child: _isLoggingIn
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                '登录',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 50,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          shape: const StadiumBorder(),
                        ),
                        onPressed: busy ? null : () => _switchLoginMode(false),
                        child: const Text('用验证码登录'),
                      ),
                    ),
                  ] else ...[
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: colorScheme.outline),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 68,
                            child: TextField(
                              controller: _areaController,
                              enabled: !busy,
                              keyboardType: TextInputType.phone,
                              textAlign: TextAlign.center,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              decoration: const InputDecoration(
                                prefixText: '+',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                              ),
                            ),
                          ),
                          Container(
                            height: 34,
                            width: 1,
                            color: colorScheme.outlineVariant,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextField(
                              controller: _phoneController,
                              enabled: !busy,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [
                                AutofillHints.telephoneNumber,
                              ],
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(20),
                              ],
                              decoration: const InputDecoration(
                                hintText: '输入手机号',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_challengeNumber != null) ...[
                      const SizedBox(height: 18),
                      TextField(
                        controller: _codeController,
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(12),
                        ],
                        onSubmitted: (_) => _loginWithSms(),
                        decoration: const InputDecoration(
                          hintText: '输入短信验证码',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 15,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 56,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                        ),
                        onPressed: busy
                            ? null
                            : _challengeNumber == null
                            ? _requestSmsCode
                            : _loginWithSms,
                        child: _isRequestingCode || _isLoggingIn
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _challengeNumber == null ? '获取验证码' : '登录',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                      ),
                    ),
                    if (_challengeNumber != null) ...[
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: busy || _countdown > 0
                              ? null
                              : _requestSmsCode,
                          child: Text(
                            _countdown > 0 ? '$_countdown 秒后重新获取' : '重新获取验证码',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 50,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          shape: const StadiumBorder(),
                        ),
                        onPressed: busy ? null : () => _switchLoginMode(true),
                        child: const Text('用账号密码登录'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
