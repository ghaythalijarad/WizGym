import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/auth/auth_session.dart';
import '../../core/config/app_config.dart';
import '../../core/localization/app_locale_controller.dart';
import '../../core/models/app_role.dart';
import '../../shared/widgets/app_background.dart';
import '../../shared/widgets/otp_input.dart';
import '../../shared/widgets/animated_logo.dart';
import '../../shared/widgets/feature_highlight.dart';
import '../../shared/widgets/password_strength_indicator.dart';
import '../../shared/widgets/countdown_timer.dart';

class AuthGatePage extends StatefulWidget {
  const AuthGatePage({
    super.key,
    required this.onAuthenticated,
    required this.localeController,
  });

  final ValueChanged<AuthSession> onAuthenticated;
  final AppLocaleController localeController;

  @override
  State<AuthGatePage> createState() => _AuthGatePageState();
}

enum _AuthMode { login, signup }

enum _EntryStep { entry, role, form }

enum _EntryAction { signup, login }

class _AuthGatePageState extends State<AuthGatePage>
    with SingleTickerProviderStateMixin {
  // ── controllers ─────────────────────────────────────────────
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();

  // ── state ────────────────────────────────────────────────────
  _AuthMode _mode = _AuthMode.login;
  _EntryStep _step = _EntryStep.entry;
  _EntryAction? _entryAction;
  bool _isForgotPassword = false;
  bool _isLoading = false;
  String? _error;
  String? _success;
  bool _otpSent = false;
  bool _phoneVerified = false;
  bool? _accountExists;
  String? _sessionId;
  AppRole _selectedRole = AppRole.user;
  bool _passwordVisible = false;
  String _otpValue = '';

  // ── animation ────────────────────────────────────────────────
  late final AnimationController _animCtrl;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  bool get _isArabic => widget.localeController.isArabic;
  TextDirection get _textDirection =>
      _isArabic ? TextDirection.rtl : TextDirection.ltr;
  bool get _directLoginMode => _mode == _AuthMode.login && !_isForgotPassword;
  bool get _otpFlowMode => !_directLoginMode;
  int? get _totalSteps {
    if (_step != _EntryStep.form) return null;
    if (_directLoginMode) return null;
    return 2;
  }

  int get _currentStepIndex => _otpSent ? 1 : 0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _buildAnims(forward: true);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  void _buildAnims({bool forward = true}) {
    _slideAnim = Tween<Offset>(
      begin: forward ? const Offset(0.06, 0) : const Offset(-0.06, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
  }

  void _animateForward(VoidCallback change) {
    _animCtrl.reset();
    _buildAnims(forward: true);
    setState(change);
    _animCtrl.forward();
  }

  void _animateBack(VoidCallback change) {
    _animCtrl.reset();
    _buildAnims(forward: false);
    setState(change);
    _animCtrl.forward();
  }

  // ── helpers ──────────────────────────────────────────────────
  Uri _api(String path) {
    final base = AppConfig.apiBaseUrl.endsWith('/')
        ? AppConfig.apiBaseUrl
        : '${AppConfig.apiBaseUrl}/';
    return Uri.parse('$base$path');
  }

  String _normalizePhoneInput(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.startsWith('0') && digits.length == 11 && digits[1] == '7') {
      digits = '964${digits.substring(1)}';
    } else if (digits.startsWith('7') && digits.length == 10) {
      digits = '964$digits';
    }
    if (digits.isEmpty) return '';
    return '+$digits';
  }

  String _extractError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'];
        if (message is String && message.trim().isNotEmpty) return message;
        if (message is List) {
          final text = message.map((e) => e.toString()).join('\n').trim();
          if (text.isNotEmpty) return text;
        }
      }
    } catch (_) {}
    final body = response.body.trim();
    if (body.isNotEmpty) return body;
    return 'حدث خطأ غير متوقع (${response.statusCode})';
  }

  void _resetFeedback() {
    _error = null;
    _success = null;
  }

  void _resetOtpStage() {
    _otpSent = false;
    _phoneVerified = false;
    _accountExists = null;
    _otpValue = '';
    _sessionId = null;
  }

  void _goToEntry() {
    _animateBack(() {
      _step = _EntryStep.entry;
      _entryAction = null;
      _mode = _AuthMode.login;
      _selectedRole = AppRole.user;
      _isForgotPassword = false;
      _resetOtpStage();
      _resetFeedback();
    });
  }

  void _selectEntryAction(_EntryAction action) {
    _animateForward(() {
      _entryAction = action;
      _isForgotPassword = false;
      _resetOtpStage();
      _resetFeedback();
      _selectedRole = AppRole.user;
      _mode =
          action == _EntryAction.signup ? _AuthMode.signup : _AuthMode.login;
      _step = _EntryStep.role;
    });
  }

  void _selectRole(AppRole role) {
    _animateForward(() {
      _selectedRole = role;
      _mode = _entryAction == _EntryAction.signup
          ? _AuthMode.signup
          : _AuthMode.login;
      _step = _EntryStep.form;
      _passwordController.clear();
      _passwordVisible = false;
      _resetFeedback();
    });
  }

  String _t({required String ar, required String en}) => _isArabic ? ar : en;

  // ── API ──────────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    setState(() {
      _isLoading = true;
      _resetFeedback();
    });
    if (!_otpFlowMode) {
      setState(() {
        _isLoading = false;
        _error = 'رمز التحقق مطلوب فقط لإنشاء حساب جديد أو استعادة كلمة السر.';
      });
      return;
    }
    final normalizedPhone = _normalizePhoneInput(_phoneController.text);
    if (normalizedPhone.isEmpty) {
      setState(() {
        _error = 'يرجى إدخال رقم هاتف صحيح';
        _isLoading = false;
      });
      return;
    }
    _phoneController.value = TextEditingValue(
      text: normalizedPhone,
      selection: TextSelection.collapsed(offset: normalizedPhone.length),
    );
    try {
      final response = await http
          .post(
            _api('auth/phone/send-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phoneNumber': normalizedPhone}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        _animateForward(() {
          _otpSent = true;
          _phoneVerified = false;
          _accountExists = null;
          _otpValue = '';
          _isLoading = false;
          _sessionId = (data['sessionId'] ?? '').toString();
          _success = _isForgotPassword
              ? 'تم إرسال رمز الاستعادة. أدخل الرمز وكلمة السر الجديدة.'
              : 'تم إرسال رمز التفعيل على هاتفك.';
        });
      } else {
        setState(() {
          _isLoading = false;
          _error = _extractError(response);
        });
      }
    } catch (error) {
      setState(() {
        _isLoading = false;
        _error = _networkErrorMessage(error);
      });
    }
  }

  Future<bool> _confirmRoleMismatch(
      {required AppRole actual, required AppRole selected}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الدور غير مطابق'),
        content: Text(
            'هذا الرقم مسجل كـ "${actual.labelAr}" وليس "${selected.labelAr}".'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('التبديل والمتابعة')),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _finishWithAuthResponse(
      {required http.Response response,
      required String normalizedPhone}) async {
    if (response.statusCode != 200 && response.statusCode != 201) {
      final message = _extractError(response);
      final expired = message.contains('expired') ||
          message.contains('verified') ||
          message.contains('انتهت');
      setState(() {
        _isLoading = false;
        if (expired) {
          _phoneVerified = false;
          _accountExists = null;
          _otpSent = false;
        }
        _error = expired ? 'انتهت صلاحية التحقق. أعد طلب رمز جديد.' : message;
      });
      return;
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final profile = (data['profile'] as Map?)?.cast<String, dynamic>();
    final token = (data['token'] ?? '').toString();
    final refreshToken = (data['refreshToken'] ?? '').toString();
    final userId = (profile?['id'] ?? '').toString();
    final phoneNumber = (profile?['phoneNumber'] ?? normalizedPhone).toString();
    final displayName = (profile?['displayName'] ?? '').toString();
    final actualRole = AppRole.fromApi((profile?['role'] ?? 'USER').toString());

    if (token.isEmpty || refreshToken.isEmpty || userId.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'استجابة الدخول غير مكتملة من الخادم';
      });
      return;
    }
    if (_mode == _AuthMode.login && actualRole != _selectedRole) {
      final shouldSwitch = await _confirmRoleMismatch(
          actual: actualRole, selected: _selectedRole);
      if (!shouldSwitch) {
        setState(() => _isLoading = false);
        return;
      }
      setState(() => _selectedRole = actualRole);
    }
    if (!mounted) return;
    widget.onAuthenticated(AuthSession(
      token: token,
      refreshToken: refreshToken,
      userId: userId,
      phoneNumber: phoneNumber,
      displayName: displayName,
      role: actualRole,
    ));
  }

  Future<void> _loginDirect() async {
    setState(() {
      _isLoading = true;
      _resetFeedback();
    });
    final normalizedPhone = _normalizePhoneInput(_phoneController.text);
    if (normalizedPhone.isEmpty) {
      setState(() {
        _error = 'يرجى إدخال رقم هاتف صحيح';
        _isLoading = false;
      });
      return;
    }
    final password = _passwordController.text.trim();
    if (password.length < 6) {
      setState(() {
        _error = 'كلمة السر يجب أن تكون 6 أحرف/أرقام على الأقل';
        _isLoading = false;
      });
      return;
    }
    try {
      final response = await http
          .post(
            _api('auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phoneNumber': normalizedPhone,
              'role': _selectedRole.apiValue,
              'password': password
            }),
          )
          .timeout(const Duration(seconds: 10));
      await _finishWithAuthResponse(
          response: response, normalizedPhone: normalizedPhone);
    } catch (error) {
      setState(() {
        _isLoading = false;
        _error = _networkErrorMessage(error);
      });
    }
  }

  Future<void> _completeOtpFlow() async {
    setState(() {
      _isLoading = true;
      _resetFeedback();
    });
    if (!_otpFlowMode) {
      setState(() {
        _isLoading = false;
        _error = 'رمز التحقق مطلوب فقط لإنشاء حساب جديد أو استعادة كلمة السر.';
      });
      return;
    }
    final normalizedPhone = _normalizePhoneInput(_phoneController.text);
    if (normalizedPhone.isEmpty) {
      setState(() {
        _error = 'يرجى إدخال رقم هاتف صحيح';
        _isLoading = false;
        _otpSent = false;
      });
      return;
    }
    final password = _passwordController.text.trim();
    if (password.length < 6) {
      setState(() {
        _error = 'كلمة السر يجب أن تكون 6 أحرف/أرقام على الأقل';
        _isLoading = false;
      });
      return;
    }
    try {
      if (!_phoneVerified) {
        final otp = _otpValue.trim();
        if (otp.length < 6) {
          setState(() {
            _error = 'يرجى إدخال رمز التحقق المكون من 6 أرقام';
            _isLoading = false;
          });
          return;
        }
        if (!_isForgotPassword) {
          final displayName = _displayNameController.text.trim();
          if (displayName.isEmpty) {
            setState(() {
              _isLoading = false;
              _error = _selectedRole == AppRole.owner
                  ? 'يرجى إدخال اسم مالك النادي'
                  : 'يرجى إدخال الاسم';
            });
            return;
          }
          final response = await http
              .post(
                _api('auth/signup'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'phoneNumber': normalizedPhone,
                  'role': _selectedRole.apiValue,
                  'password': password,
                  'sessionId': _sessionId ?? '',
                  'otp': otp,
                  'displayName': displayName,
                }),
              )
              .timeout(const Duration(seconds: 10));
          await _finishWithAuthResponse(
              response: response, normalizedPhone: normalizedPhone);
          return;
        }
        final verify = await http
            .post(
              _api('auth/phone/verify-otp'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'sessionId': _sessionId ?? '', 'otp': otp}),
            )
            .timeout(const Duration(seconds: 10));
        if (verify.statusCode != 200 && verify.statusCode != 201) {
          final message = _extractError(verify);
          final expired = message.contains('expired') ||
              message.contains('انتهت') ||
              message.contains('صلاحية');
          setState(() {
            _isLoading = false;
            _error = expired
                ? 'انتهت صلاحية رمز التحقق. أعد طلب رمز جديد.'
                : message;
          });
          return;
        }
        final verifyData = jsonDecode(verify.body) as Map<String, dynamic>;
        setState(() {
          _phoneVerified = true;
          _accountExists = verifyData['accountExists'] == true;
          _success = 'تم التحقق من الرمز بنجاح.';
        });
      }
      if (_isForgotPassword) {
        if (_accountExists != true) {
          setState(() {
            _isLoading = false;
            _error = 'لا يوجد حساب بهذا الدور لإعادة تعيين كلمة السر.';
          });
          return;
        }
        final resetResponse = await http
            .post(
              _api('auth/password/reset'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'phoneNumber': normalizedPhone,
                'role': _selectedRole.apiValue,
                'password': password
              }),
            )
            .timeout(const Duration(seconds: 10));
        if (resetResponse.statusCode != 200 &&
            resetResponse.statusCode != 201) {
          setState(() {
            _isLoading = false;
            _error = _extractError(resetResponse);
          });
          return;
        }
        _animateBack(() {
          _isLoading = false;
          _mode = _AuthMode.login;
          _isForgotPassword = false;
          _resetOtpStage();
          _passwordController.clear();
          _success = 'تم تحديث كلمة السر. يمكنك تسجيل الدخول الآن.';
        });
        return;
      }
      if (_accountExists == true) {
        setState(() {
          _isLoading = false;
          _error = 'يوجد حساب بهذا الدور. استخدم تسجيل الدخول.';
          _mode = _AuthMode.login;
          _isForgotPassword = false;
          _resetOtpStage();
        });
        return;
      }
      setState(() {
        _isLoading = false;
        _error = 'حدث خطأ غير متوقع. حاول مرة أخرى.';
      });
    } catch (error) {
      setState(() {
        _isLoading = false;
        _error = _networkErrorMessage(error);
      });
    }
  }

  String _networkErrorMessage(Object error) {
    const base = AppConfig.apiBaseUrl;
    if (error is TimeoutException) {
      return _isArabic
          ? 'انتهت مهلة الاتصال بالخادم. تأكد من تشغيل السيرفر ثم حاول مرة أخرى.'
          : 'Request timed out. Make sure the server is running and try again.';
    }
    final text = error.toString().toLowerCase();
    final unreachable = text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection refused') ||
        text.contains('network is unreachable');
    final msg = unreachable
        ? (_isArabic ? 'تعذر الاتصال بالخادم.' : 'Could not reach the server.')
        : (_isArabic
            ? 'حدث خطأ في الاتصال. حاول مرة أخرى.'
            : 'A network error occurred. Please try again.');
    return kDebugMode ? '$msg\n\nAPI: $base' : msg;
  }

  // ── build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stageTitle = _step == _EntryStep.entry
        ? _t(ar: 'مرحباً بك', en: 'Welcome')
        : _step == _EntryStep.role
            ? _t(ar: 'اختر دورك', en: 'Choose your role')
            : (_directLoginMode
                ? _t(ar: 'تسجيل الدخول', en: 'Sign in')
                : _isForgotPassword
                    ? _t(ar: 'استعادة كلمة السر', en: 'Reset password')
                    : _t(ar: 'إنشاء حساب', en: 'Create account'));

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 38,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: _step == _EntryStep.form
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: [
                      // ── header ──────────────────────
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _isLoading
                                ? null
                                : widget.localeController.toggle,
                            icon: const Icon(Icons.language_rounded, size: 16),
                            label: Text(_isArabic ? 'EN' : 'AR',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const Spacer(),
                          Text('WizGym',
                              style: Theme.of(context)
                                  .textTheme
                                  .displaySmall
                                  ?.copyWith(
                                      fontSize: 26, letterSpacing: -0.5)),
                          const SizedBox(width: 10),
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.fitness_center_rounded,
                                color: scheme.onPrimary, size: 22),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _t(
                          ar: 'أنشئ حسابك أو سجّل الدخول حسب دورك',
                          en: 'Create your account or sign in based on your role',
                        ),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 20),

                      // ── card ─────────────────────────
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: scheme.outlineVariant),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.shadow.withValues(alpha: 0.12),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Directionality(
                          textDirection: _textDirection,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // card title row
                              Row(
                                children: [
                                  if (_step != _EntryStep.entry)
                                    Padding(
                                      padding: const EdgeInsetsDirectional.only(
                                          end: 6),
                                      child: IconButton.outlined(
                                        onPressed:
                                            _isLoading ? null : _goToEntry,
                                        icon: const Icon(
                                            Icons.arrow_back_ios_new_rounded,
                                            size: 16),
                                        style: IconButton.styleFrom(
                                          minimumSize: const Size(34, 34),
                                          padding: EdgeInsets.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: Text(stageTitle,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                  ),
                                  if (_totalSteps != null)
                                    _StepDots(
                                      total: _totalSteps!,
                                      current: _currentStepIndex,
                                      activeColor: scheme.primary,
                                      inactiveColor: scheme.outline,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // animated content
                              SlideTransition(
                                position: _slideAnim,
                                child: FadeTransition(
                                  opacity: _fadeAnim,
                                  child: _buildStepContent(scheme),
                                ),
                              ),

                              // feedback banners
                              if (_success != null) ...[
                                const SizedBox(height: 14),
                                _FeedbackBanner(
                                    text: _success!,
                                    isError: false,
                                    scheme: scheme),
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: 14),
                                _FeedbackBanner(
                                    text: _error!,
                                    isError: true,
                                    scheme: scheme),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // Footer section - only show when not on entry step
                      if (_step == _EntryStep.form) ...[
                        const SizedBox(height: 24),
                        // Divider with text
                        Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: scheme.outlineVariant
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                _directLoginMode
                                    ? _t(
                                        ar: 'ليس لديك حساب؟',
                                        en: "Don't have an account?")
                                    : _t(
                                        ar: 'لديك حساب بالفعل؟',
                                        en: 'Already have an account?'),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: scheme.outlineVariant
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Switch mode button
                        OutlinedButton(
                          onPressed: _isLoading
                              ? null
                              : () {
                                  setState(() {
                                    if (_directLoginMode) {
                                      _mode = _AuthMode.signup;
                                      _isForgotPassword = false;
                                    } else {
                                      _mode = _AuthMode.login;
                                      _isForgotPassword = false;
                                    }
                                    _resetOtpStage();
                                    _resetFeedback();
                                  });
                                },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _directLoginMode
                                ? _t(
                                    ar: 'إنشاء حساب جديد',
                                    en: 'Create new account')
                                : _t(ar: 'تسجيل الدخول', en: 'Sign in'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent(ColorScheme scheme) {
    if (_step == _EntryStep.entry) return _buildEntry(scheme);
    if (_step == _EntryStep.role) return _buildRoleSelector(scheme);
    if (_directLoginMode) return _buildLoginForm(scheme);
    if (!_otpSent) return _buildPhoneStep(scheme);
    return _buildOtpStep(scheme);
  }

  // ── ENTRY ────────────────────────────────────────────────────
  Widget _buildEntry(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hero section with animated logo
        Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primary.withValues(alpha: 0.12),
                scheme.secondary.withValues(alpha: 0.08),
                scheme.tertiary.withValues(alpha: 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: scheme.primary.withValues(alpha: 0.2), width: 1),
          ),
          child: Column(
            children: [
              const AnimatedLogo(size: 72, showText: false),
              const SizedBox(height: 16),
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [scheme.primary, scheme.secondary],
                ).createShader(bounds),
                child: Text(
                  _t(
                      ar: 'ابدأ رحلتك الرياضية',
                      en: 'Start Your Fitness Journey'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _t(
                    ar: 'انضم إلى آلاف المتدربين والمدربين',
                    en: 'Join thousands of trainees and trainers'),
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Feature highlights
        FeatureHighlightsSection(isArabic: _isArabic),

        const SizedBox(height: 8),

        // Create account button with gradient
        _GradientButton(
          onPressed:
              _isLoading ? null : () => _selectEntryAction(_EntryAction.signup),
          colors: [scheme.primary, scheme.primary.withValues(alpha: 0.8)],
          shadowColor: scheme.primary.withValues(alpha: 0.4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_add_rounded, color: scheme.onPrimary, size: 22),
              const SizedBox(width: 10),
              Text(_t(ar: 'إنشاء حساب جديد', en: 'Create new account'),
                  style: TextStyle(
                      color: scheme.onPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Sign in button
        _GradientButton(
          onPressed:
              _isLoading ? null : () => _selectEntryAction(_EntryAction.login),
          colors: null,
          borderColor: scheme.outline,
          shadowColor: Colors.transparent,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.login_rounded, color: scheme.onSurface, size: 22),
              const SizedBox(width: 10),
              Text(_t(ar: 'لديّ حساب بالفعل', en: 'I already have an account'),
                  style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Terms hint
        Text(
          _t(
            ar: 'بالمتابعة، أنت توافق على شروط الاستخدام',
            en: 'By continuing, you agree to our Terms of Service',
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                fontSize: 11,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── ROLE SELECTOR ────────────────────────────────────────────
  Widget _buildRoleSelector(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Subtitle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _t(
                    ar: 'اختر الدور المناسب لك للمتابعة',
                    en: 'Choose the role that fits you to continue',
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        _RoleCard(
          role: AppRole.user,
          subtitleAr: 'استكشف النوادي، انضم وظّف مدربك الخاص',
          subtitleEn: 'Explore gyms, join and hire your trainer',
          icon: Icons.directions_run_rounded,
          accent: scheme.primary,
          isSelected: false,
          onTap: _isLoading ? null : () => _selectRole(AppRole.user),
        ),
        const SizedBox(height: 10),
        _RoleCard(
          role: AppRole.trainer,
          subtitleAr: 'انضم لحتى 4 نوادٍ وتابع عملاءك',
          subtitleEn: 'Join up to 4 gyms and manage clients',
          icon: Icons.fitness_center_rounded,
          accent: scheme.secondary,
          isSelected: false,
          onTap: _isLoading ? null : () => _selectRole(AppRole.trainer),
        ),
        const SizedBox(height: 10),
        _RoleCard(
          role: AppRole.owner,
          subtitleAr: 'أضف مرافق ومنتجات وحدد خدمات النادي',
          subtitleEn: 'Add facilities, products and manage the gym',
          icon: Icons.storefront_rounded,
          accent: scheme.tertiary,
          isSelected: false,
          onTap: _isLoading ? null : () => _selectRole(AppRole.owner),
        ),
        const SizedBox(height: 16),

        // Footer hint
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.swap_horiz_rounded,
                size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              _t(
                ar: 'يمكنك تغيير الدور لاحقاً',
                en: 'You can change role later',
              ),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }

  // ── LOGIN FORM ───────────────────────────────────────────────
  Widget _buildLoginForm(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PhoneField(controller: _phoneController, isArabic: _isArabic),
        const SizedBox(height: 14),
        _PasswordField(
          controller: _passwordController,
          visible: _passwordVisible,
          label: _t(ar: 'كلمة السر', en: 'Password'),
          onToggle: () => setState(() => _passwordVisible = !_passwordVisible),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _isLoading ? null : _loginDirect,
            child: _isLoading
                ? const _Spinner()
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text(_t(ar: 'تسجيل الدخول', en: 'Sign in')),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            onPressed: _isLoading
                ? null
                : () => setState(() {
                      _isForgotPassword = true;
                      _mode = _AuthMode.login;
                      _resetOtpStage();
                      _passwordController.clear();
                      _resetFeedback();
                    }),
            icon: const Icon(Icons.help_outline_rounded, size: 18),
            label: Text(_t(ar: 'نسيت كلمة السر؟', en: 'Forgot password?')),
          ),
        ),
      ],
    );
  }

  // ── PHONE STEP ───────────────────────────────────────────────
  Widget _buildPhoneStep(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Info banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: scheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _isForgotPassword
                      ? Icons.lock_reset_rounded
                      : Icons.verified_user_outlined,
                  size: 20,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t(
                        ar: _isForgotPassword
                            ? 'استعادة كلمة السر'
                            : 'التحقق من الهاتف',
                        en: _isForgotPassword
                            ? 'Password Recovery'
                            : 'Phone Verification',
                      ),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _t(
                        ar: _isForgotPassword
                            ? 'سنرسل رمز التحقق لاستعادة حسابك'
                            : 'سنرسل رمز تأكيد مكون من 6 أرقام',
                        en: _isForgotPassword
                            ? 'We\'ll send a code to recover your account'
                            : 'We\'ll send a 6-digit verification code',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        _PhoneField(controller: _phoneController, isArabic: _isArabic),
        const SizedBox(height: 20),

        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _isLoading ? null : _sendOtp,
            child: _isLoading
                ? const _Spinner()
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.send_rounded, size: 18),
                      const SizedBox(width: 10),
                      Text(_isForgotPassword
                          ? _t(ar: 'إرسال رمز الاستعادة', en: 'Send reset code')
                          : _t(ar: 'إرسال رمز التفعيل', en: 'Send OTP')),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // ── OTP + PASSWORD STEP ──────────────────────────────────────
  Widget _buildOtpStep(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Phone number display with edit hint
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.phone_android_rounded,
                    size: 18, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t(ar: 'تم إرسال الرمز إلى', en: 'Code sent to'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _phoneController.text,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // OTP Input
        OtpInput(
          onCompleted: (v) => setState(() => _otpValue = v),
          onChanged: (v) => setState(() => _otpValue = v),
        ),
        const SizedBox(height: 12),

        // Countdown timer or resend button
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: CountdownTimer(
            durationSeconds: 60,
            onComplete: () {},
            onResend: _isLoading ? null : _sendOtp,
          ),
        ),
        const SizedBox(height: 20),

        // Password field with strength indicator for signup
        _PasswordField(
          controller: _passwordController,
          visible: _passwordVisible,
          label: _isForgotPassword
              ? _t(ar: 'كلمة السر الجديدة', en: 'New password')
              : _t(ar: 'كلمة السر', en: 'Password'),
          onToggle: () => setState(() => _passwordVisible = !_passwordVisible),
          showStrength: _mode == _AuthMode.signup || _isForgotPassword,
          isArabic: _isArabic,
        ),

        if (_mode == _AuthMode.signup) ...[
          const SizedBox(height: 14),
          // Display name field with better styling
          TextField(
            controller: _displayNameController,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: _selectedRole == AppRole.owner
                  ? _t(ar: 'اسم مالك النادي', en: 'Owner name')
                  : _t(ar: 'الاسم', en: 'Name'),
              prefixIcon: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.secondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.badge_outlined,
                  size: 18,
                  color: scheme.secondary,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _isLoading
                      ? null
                      : () => _animateBack(() {
                            _resetOtpStage();
                            _passwordController.clear();
                            _resetFeedback();
                          }),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: Text(_t(ar: 'تغيير الرقم', en: 'Change')),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _isLoading ? null : _completeOtpFlow,
                  child: _isLoading
                      ? const _Spinner()
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_isForgotPassword
                                ? _t(ar: 'تحديث', en: 'Update')
                                : _t(ar: 'إنشاء الحساب', en: 'Create')),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward_rounded, size: 18),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════
// Private sub-widgets (file-private, no export)
// ═══════════════════════════════════════════════

class _StepDots extends StatelessWidget {
  const _StepDots({
    required this.total,
    required this.current,
    required this.activeColor,
    required this.inactiveColor,
  });
  final int total;
  final int current;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: active ? activeColor : inactiveColor,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

class _GradientButton extends StatefulWidget {
  const _GradientButton({
    required this.onPressed,
    required this.child,
    required this.colors,
    required this.shadowColor,
    this.borderColor,
  });
  final VoidCallback? onPressed;
  final Widget child;
  final List<Color>? colors;
  final Color? borderColor;
  final Color shadowColor;

  @override
  State<_GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<_GradientButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null;

    final s = _isPressed ? 0.98 : 1.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 54,
      transform: Matrix4.identity()..scaleByDouble(s, s, 1.0, 1.0),
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: widget.colors != null && !isDisabled
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.colors!,
              )
            : null,
        color: widget.colors == null
            ? Colors.transparent
            : isDisabled
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : null,
        border: widget.borderColor != null
            ? Border.all(color: widget.borderColor!, width: 1.5)
            : null,
        borderRadius: BorderRadius.circular(16),
        boxShadow: !isDisabled && widget.shadowColor != Colors.transparent
            ? [
                BoxShadow(
                  color: widget.shadowColor,
                  blurRadius: _isPressed ? 8 : 16,
                  offset: Offset(0, _isPressed ? 2 : 6),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPressed,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          borderRadius: BorderRadius.circular(16),
          child: Center(child: widget.child),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.subtitleAr,
    required this.subtitleEn,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.isSelected = false,
  });
  final AppRole role;
  final String subtitleAr;
  final String subtitleEn;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  final bool isSelected;

  String _labelEn(AppRole r) {
    switch (r) {
      case AppRole.admin:
        return 'Admin';
      case AppRole.owner:
        return 'Gym Owner';
      case AppRole.trainer:
        return 'Trainer';
      case AppRole.user:
        return 'Trainee';
      case AppRole.trainee:
        return 'Trainee';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isArabic = Directionality.of(context) == TextDirection.rtl;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: isSelected
                ? accent.withValues(alpha: 0.15)
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? accent : accent.withValues(alpha: 0.2),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accent.withValues(alpha: 0.25),
                        accent.withValues(alpha: 0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: accent, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isArabic ? role.labelAr : _labelEn(role),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        isArabic ? subtitleAr : subtitleEn,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: accent,
                    size: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({required this.controller, required this.isArabic});
  final TextEditingController controller;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.phone,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        decoration: InputDecoration(
          labelText: isArabic ? 'رقم الهاتف' : 'Phone number',
          hintText: '7XX XXX XXXX',
          hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
          // Phone icon on the right (suffix for LTR)
          suffixIcon: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.phone_outlined,
              size: 18,
              color: scheme.primary,
            ),
          ),
          // Country code on the left (prefix for LTR)
          prefixIcon: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '🇮🇶',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(width: 6),
                Text(
                  '+964',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.visible,
    required this.label,
    required this.onToggle,
    this.showStrength = false,
    this.isArabic = true,
  });
  final TextEditingController controller;
  final bool visible;
  final String label;
  final VoidCallback onToggle;
  final bool showStrength;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          obscureText: !visible,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: scheme.primary,
              ),
            ),
            suffixIcon: IconButton(
              onPressed: onToggle,
              icon: Icon(
                  visible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant),
              tooltip: visible ? 'إخفاء' : 'إظهار',
            ),
          ),
        ),
        if (showStrength)
          PasswordStrengthIndicator(
            password: controller.text,
            isArabic: isArabic,
          ),
      ],
    );
  }
}

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner(
      {required this.text, required this.isError, required this.scheme});
  final String text;
  final bool isError;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final bg = isError
        ? scheme.errorContainer.withValues(alpha: 0.8)
        : scheme.primaryContainer.withValues(alpha: 0.5);
    final border = isError
        ? scheme.error.withValues(alpha: 0.5)
        : scheme.primary.withValues(alpha: 0.5);
    final textColor = isError ? scheme.error : scheme.primary;
    final icon = isError
        ? Icons.error_outline_rounded
        : Icons.check_circle_outline_rounded;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.9 + (0.1 * value),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: (isError ? scheme.error : scheme.primary)
                  .withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: (isError ? scheme.error : scheme.primary)
                    .withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: textColor, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: textColor, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2.2));
}
