import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/auth_controller.dart';
import '../data/auth_api.dart';
import '../data/session.dart';
import 'widgets/auth_message.dart';
import 'widgets/phone_field.dart';

/// Forgotten PIN (from Login, or from the unlock screen — also while locked
/// out): phone → SMS code → new PIN. On success the app signs in with the new
/// PIN and the router opens the shop.
class PinResetScreen extends ConsumerStatefulWidget {
  const PinResetScreen({super.key});

  @override
  ConsumerState<PinResetScreen> createState() => _PinResetScreenState();
}

class _PinResetScreenState extends ConsumerState<PinResetScreen> {
  static const _resendAfter = 60;

  late final _phone = TextEditingController(text: _localPhone(ref.read(sessionProvider).phone));
  final _otp = TextEditingController();
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  int _resendIn = 0;
  Timer? _timer;
  String? _error;

  /// "+95971234567" → "971234567" (the field shows +95 itself).
  static String _localPhone(String e164) => e164.startsWith('+95') ? e164.substring(3) : e164;

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [_phone, _otp, _pin, _pin2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> _run(Future<void> Function(AuthController c) action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(authControllerProvider.notifier));
      return true;
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    if (!await _run((c) => c.requestOtp(_phone.text, OtpPurpose.reset)) || !mounted) return;
    setState(() {
      _codeSent = true;
      _resendIn = _resendAfter;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _resendIn <= 0) {
        t.cancel();
      } else {
        setState(() => _resendIn--);
      }
    });
  }

  Future<void> _save() async {
    if (_pin.text != _pin2.text) {
      setState(() => _error = 'PIN အသစ် နှစ်ခါ မတူပါ။');
      return;
    }
    // Success changes the auth status; the router leaves this screen.
    await _run((c) => c.resetPin(rawPhone: _phone.text, otp: _otp.text, newPin: _pin.text));
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      final locked = ref.read(authControllerProvider).status == AuthStatus.locked;
      context.go(locked ? Routes.unlock : Routes.login);
    }
  }

  Widget _digits(TextEditingController c, String label, {bool obscure = false}) => LabeledField(
        label: label,
        child: AppInput(
          controller: c,
          height: 52,
          radius: 14,
          fontSize: 16,
          hint: obscure ? '••••••' : '000000',
          obscure: obscure,
          keyboardType: TextInputType.number,
          semanticLabel: label,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(title: 'PIN အသစ် သတ်မှတ်မယ်', onBack: _back),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              children: [
                Text('ဆိုင်ဖွင့်တုန်းက ဖုန်းနံပါတ်ကို SMS ကုဒ် ပို့ပေးပါမယ်။ PIN အသစ်နဲ့ ဒီဖုန်းကို ပြန်ဝင်ပေးပါမယ်။',
                    style: AppText.s(14, color: AppColors.muted)),
                const SizedBox(height: 18),
                LabeledField(label: 'ဖုန်းနံပါတ်', child: PhoneField(controller: _phone)),
                if (_codeSent) ...[
                  const SizedBox(height: 16),
                  _digits(_otp, 'SMS ကုဒ်'),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _resendIn == 0 && !_busy ? _sendCode : null,
                      child: Text(_resendIn == 0 ? 'ကုဒ် ပြန်ပို့မယ်' : 'ကုဒ် ပြန်ပို့မယ် ($_resendIn)',
                          style: AppText.s(13, weight: AppText.w600, color: AppColors.primary)),
                    ),
                  ),
                  _digits(_pin, 'PIN အသစ် (၆ လုံး)', obscure: true),
                  const SizedBox(height: 16),
                  _digits(_pin2, 'PIN အသစ် ထပ်ရိုက်ပါ', obscure: true),
                  const SizedBox(height: 8),
                  Text('PIN ပြောင်းရင် ဒီဆိုင်က တခြားဖုန်းတွေမှာလည်း PIN အသစ်နဲ့ ပြန်ဝင်ရပါမယ်။',
                      style: AppText.s(12, color: AppColors.muted)),
                ],
                if (_error != null) ...[const SizedBox(height: 16), AuthMessage(_error!)],
                const SizedBox(height: 20),
                PrimaryButton(
                  label: _busy
                      ? 'ခဏစောင့်ပါ…'
                      : _codeSent
                          ? 'PIN အသစ် သိမ်းမယ်'
                          : 'ကုဒ်ပို့မယ်',
                  onPressed: _busy ? null : (_codeSent ? _save : _sendCode),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
