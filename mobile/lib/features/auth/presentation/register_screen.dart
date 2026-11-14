import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/features/features_providers.dart';
import '../../../core/features/shop_template.dart';
import '../../../core/router/routes.dart';
import '../../../core/sync/sync_limits.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_switch_tile.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/numeric_keypad.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/auth_controller.dart';
import '../data/auth_api.dart';
import '../data/session.dart';
import 'widgets/auth_message.dart';
import 'widgets/phone_field.dart';

enum CatalogStart { preset, quick, import }

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.initialStep = 1});

  final int initialStep;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  static const _resendAfter = 60;

  late int _step;
  late String _type;
  late CatalogStart _start;
  late final TextEditingController _shopName;
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  String _pin = '';

  /// Signed in already: opened from Settings to change the shop template.
  late final bool _signedIn;
  bool _codeSent = false;
  int _resendIn = 0;
  Timer? _timer;
  bool _busy = false;
  String? _error;

  static CatalogStart _defaultStart(ShopTemplate t) =>
      t.features.presetCatalog && t.presetCount > 0 ? CatalogStart.preset : CatalogStart.quick;

  @override
  void initState() {
    super.initState();
    _signedIn = ref.read(authControllerProvider).status == AuthStatus.unlocked;
    _step = widget.initialStep.clamp(1, 4);
    _type = ref.read(shopTemplateProvider).id;
    _start = _defaultStart(ShopTemplate.byId(_type));
    _shopName = TextEditingController(text: _signedIn ? ref.read(sessionProvider).shopName : '');
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shopName.dispose();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  void _back() {
    if (_step > 1 && !_signedIn) {
      setState(() {
        _step--;
        _error = null;
      });
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go(_signedIn ? Routes.dashboard : Routes.login);
    }
  }

  /// Runs [action] with a busy state; an [AuthFailure] becomes the message.
  Future<bool> _run(Future<void> Function(AuthController c) action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(authControllerProvider.notifier));
      return true;
    } on AuthFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          if (e.code == 'otp_invalid') {
            _step = 1;
            _otp.clear();
          }
        });
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    final ok = await _run((c) => c.requestOtp(_phone.text, OtpPurpose.register));
    if (!ok || !mounted) return;
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

  void _fail(String message) => setState(() => _error = message);

  Future<void> _next() async {
    if (_signedIn) return _saveTemplate();
    if (_step == 1) {
      if (!_codeSent) return _sendCode();
      if (_otp.text.length != 6) return _fail('SMS ကုဒ် ၆ လုံး ထည့်ပါ။');
    }
    if (_step == 2) {
      final error = ref.read(syncLimitsProvider).checkText('tenants.name', _shopName.text, label: 'ဆိုင်အမည်') ??
          (_shopName.text.trim().isEmpty ? 'ဆိုင်အမည် ထည့်ပါ။' : null);
      if (error != null) return _fail(error);
    }
    if (_step < 4) {
      setState(() {
        _step++;
        _error = null;
      });
      return;
    }
    if (_pin.length != 6) return _fail(AuthMessages.badPin);
    // Success: the auth status becomes unlocked and the router opens the app.
    await _run((c) => c.register(
          rawPhone: _phone.text,
          otp: _otp.text,
          shopName: _shopName.text,
          templateId: _type,
          pin: _pin,
          importPresets: _start == CatalogStart.preset,
        ));
  }

  /// Settings → change shop type: applies the template's feature flags.
  void _saveTemplate() {
    ref.read(shopTemplateProvider.notifier).select(_type);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.dashboard);
    }
  }

  String get _buttonLabel {
    if (_signedIn) return 'သိမ်းမယ်';
    if (_busy) return 'ခဏစောင့်ပါ…';
    if (_step == 1 && !_codeSent) return 'ကုဒ်ပို့မယ်';
    return _step < 4 ? 'ဆက်သွားမယ်' : 'ဆိုင်ဖွင့်မယ်';
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 16 + top, 20, 0),
            child: Row(
              children: [
                AppIconButton(icon: AppIcons.back, onPressed: _back, semanticLabel: 'နောက်သို့'),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_signedIn ? 'ဆိုင်အမျိုးအစား ပြောင်းမယ်' : 'အဆင့် $_step / 4',
                      style: AppText.s(14, color: AppColors.muted)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: [
                for (var i = 1; i <= 4; i++) ...[
                  if (i > 1) const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: i <= _step ? AppColors.primary : AppColors.border,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 20),
              child: switch (_step) {
                1 => _StepPhone(
                    phone: _phone,
                    otp: _otp,
                    codeSent: _codeSent,
                    resendIn: _resendIn,
                    onResend: _busy ? null : _sendCode,
                  ),
                2 => _StepShopType(
                    shopName: _signedIn ? null : _shopName,
                    selected: _type,
                    onPick: (t) => setState(() {
                      _type = t.id;
                      _start = _defaultStart(t);
                    }),
                  ),
                3 => _StepCatalog(
                    template: ShopTemplate.byId(_type),
                    selected: _start,
                    onPick: (s) => setState(() => _start = s),
                  ),
                _ => _StepPin(
                    pin: _pin,
                    onKey: (k) => setState(() {
                      if (k == NumericKeypad.backspace) {
                        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
                      } else if (_pin.length < 6) {
                        _pin += k;
                      }
                    }),
                  ),
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 28 + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[AuthMessage(_error!), const SizedBox(height: 12)],
                PrimaryButton(label: _buttonLabel, onPressed: _busy ? null : _next),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle(this.title, this.subtitle, {this.size = 24, this.subSize = 14, this.gap = 4});

  final String title;
  final String subtitle;
  final double size;
  final double subSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(title, style: AppText.s(size, weight: AppText.w700))),
        SizedBox(height: gap),
        Text(subtitle, style: AppText.s(subSize, color: AppColors.muted)),
      ],
    );
  }
}

// ── Step 1: phone + OTP ────────────────────────────────────────────────────
class _StepPhone extends StatefulWidget {
  const _StepPhone({
    required this.phone,
    required this.otp,
    required this.codeSent,
    required this.resendIn,
    required this.onResend,
  });

  final TextEditingController phone;
  final TextEditingController otp;

  /// The SMS code was requested: show the 6 code boxes.
  final bool codeSent;

  /// Seconds until "send again" is allowed.
  final int resendIn;
  final VoidCallback? onResend;

  @override
  State<_StepPhone> createState() => _StepPhoneState();
}

class _StepPhoneState extends State<_StepPhone> {
  final _otpFocus = FocusNode();

  TextEditingController get _otp => widget.otp;

  @override
  void initState() {
    super.initState();
    _otp.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _otp.removeListener(_changed);
    _otpFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = _otp.text;
    final s = widget.resendIn;
    final time = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StepTitle('ဖုန်းနံပါတ် အတည်ပြုမယ်', 'SMS နဲ့ ကုဒ် ၆ လုံး ပို့ပေးပါမယ်'),
          const SizedBox(height: 18),
          LabeledField(label: 'ဖုန်းနံပါတ်', child: PhoneField(controller: widget.phone)),
          if (widget.codeSent) ..._codeBoxes(code, time),
        ],
      ),
    );
  }

  List<Widget> _codeBoxes(String code, String time) => [
          const SizedBox(height: 18),
          Text('အတည်ပြုကုဒ်', style: AppText.s(14, weight: AppText.w600)),
          const SizedBox(height: 6),
          Stack(
            children: [
              GestureDetector(
                onTap: () => _otpFocus.requestFocus(),
                child: Row(
                  children: [
                    for (var i = 0; i < 6; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 52,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: i == code.length ? AppColors.primary : AppColors.inputBorder,
                              width: 1.5,
                            ),
                          ),
                          child: Text(i < code.length ? code[i] : '',
                              style: AppText.s(20, weight: AppText.w700, height: 1.2)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Invisible input that drives the 6 boxes.
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: Semantics(
                    label: 'အတည်ပြုကုဒ်',
                    child: TextField(
                      controller: _otp,
                      focusNode: _otpFocus,
                      keyboardType: TextInputType.number,
                      showCursor: false,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: const InputDecoration.collapsed(hintText: null).copyWith(filled: false),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('ကုဒ်မရဘူးလား? ', style: AppText.s(13, color: AppColors.muted)),
              InkWell(
                onTap: widget.resendIn == 0 ? widget.onResend : null,
                child: Text(widget.resendIn == 0 ? 'ပြန်ပို့မယ်' : 'ပြန်ပို့မယ် ($time)',
                    style: AppText.s(13, weight: AppText.w600, color: AppColors.primary)),
              ),
            ],
          ),
        ];
}

// ── Step 2: shop type ──────────────────────────────────────────────────────
class _StepShopType extends StatelessWidget {
  const _StepShopType({required this.shopName, required this.selected, required this.onPick});

  /// null = no name field (changing the template of an existing shop).
  final TextEditingController? shopName;
  final String selected;
  final ValueChanged<ShopTemplate> onPick;

  @override
  Widget build(BuildContext context) {
    const all = ShopTemplate.all;
    final name = shopName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StepTitle('ဘယ်လိုဆိုင်လဲ?', 'ရွေးလိုက်တာနဲ့ ဆိုင်နဲ့ကိုက်တဲ့ feature တွေ အလိုအလျောက် ဖွင့်ပေးမယ်',
              size: 22, subSize: 13, gap: 2),
          const SizedBox(height: 14),
          if (name != null) ...[
            FieldLabel('ဆိုင်အမည်', size: 13),
            const SizedBox(height: 6),
            AppInput(controller: name, height: 46, semanticLabel: 'ဆိုင်အမည်'),
            const SizedBox(height: 14),
          ],
          for (var r = 0; r < all.length; r += 2) ...[
            if (r > 0) const SizedBox(height: 8),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _typeCard(all[r])),
                  const SizedBox(width: 8),
                  Expanded(child: r + 1 < all.length ? _typeCard(all[r + 1]) : const SizedBox()),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _typeCard(ShopTemplate t) {
    final on = t.id == selected;
    // BUG-10: "v2" (soon) templates cannot be chosen, like in Settings.
    return Semantics(
      button: true,
      selected: on,
      enabled: !t.soon,
      child: Opacity(
        opacity: t.soon ? 0.5 : 1,
        child: Material(
        color: on ? AppColors.primarySoft : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: on ? AppColors.primary : AppColors.border, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: t.soon ? null : () => onPick(t),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 92),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8), // 10 - 2px border
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          InitialAvatar(
                              initial: t.initial,
                              bg: t.tint,
                              fg: AppColors.textStrong,
                              size: 30,
                              fontSize: 14,
                              radius: 9),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(t.label, style: AppText.s(13, weight: AppText.w700, height: 1.35)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(t.desc, style: AppText.s(11, color: AppColors.muted, height: 1.45)),
                    ],
                  ),
                ),
                if (t.soon)
                  const Positioned(
                    top: 4,
                    right: 4,
                    child: TinyBadge('v2', bg: AppColors.fill, fg: AppColors.textSecondary),
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

// ── Step 3: catalog start ──────────────────────────────────────────────────
class _StepCatalog extends StatelessWidget {
  const _StepCatalog({required this.template, required this.selected, required this.onPick});

  final ShopTemplate template;
  final CatalogStart selected;
  final ValueChanged<CatalogStart> onPick;

  @override
  Widget build(BuildContext context) {
    final options = <(CatalogStart, String, String)>[
      if (template.features.presetCatalog && template.presetCount > 0)
        (
          CatalogStart.preset,
          'ကြိုတင်စာရင်း သုံးမယ် (အကြံပြု)',
          'အများဆုံးရောင်းတဲ့ ပစ္စည်း ${template.presetCount} မျိုး ထည့်ပြီးသား · ဈေးနှုန်းပဲ ထည့်ရုံ',
        ),
      (CatalogStart.quick, 'Quick Sale နဲ့ ချက်ချင်း စရောင်းမယ်', 'ဈေးနှုန်းရိုက်ပြီး ရောင်းရုံပဲ · ပစ္စည်းစာရင်း နောက်မှ ထည့်'),
      (CatalogStart.import, 'Excel ကနေ တင်မယ်', 'ရှိပြီးသား ပစ္စည်းစာရင်း ဖိုင်ကို တင်ပါ'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepTitle('ပစ္စည်းစာရင်း ဘယ်လိုစမလဲ?', '${template.label} အတွက် · နောက်မှ ပြောင်းလို့ရပါတယ်', size: 22),
          for (final o in options) ...[
            const SizedBox(height: 16),
            _option(o.$1, o.$2, o.$3),
          ],
        ],
      ),
    );
  }

  Widget _option(CatalogStart id, String title, String desc) {
    final on = id == selected;
    return Semantics(
      button: true,
      selected: on,
      child: Material(
        color: on ? AppColors.primarySoft : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: on ? AppColors.primary : AppColors.border, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onPick(id),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: on ? AppColors.primary : AppColors.subtle, width: 2),
                  ),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: on ? AppColors.primary : AppColors.transparent,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppText.s(15, weight: AppText.w700)),
                      const SizedBox(height: 2),
                      Text(desc, style: AppText.s(13, color: AppColors.muted)),
                    ],
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

// ── Step 4: PIN ────────────────────────────────────────────────────────────
class _StepPin extends StatelessWidget {
  const _StepPin({required this.pin, required this.onKey});

  final String pin;
  final ValueChanged<String> onKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StepTitle('PIN နံပါတ် သတ်မှတ်မယ်', 'App ဖွင့်တိုင်း ဒီ PIN နဲ့ ဝင်ရပါမယ်'),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 6; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < pin.length ? AppColors.text : AppColors.transparent,
                      border: Border.all(color: i < pin.length ? AppColors.text : AppColors.subtle, width: 2),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          NumericKeypad(
            keys: NumericKeypad.pinKeys,
            keyHeight: 60,
            gap: 10,
            radius: 14,
            keyColor: AppColors.fill,
            onKey: onKey,
          ),
        ],
      ),
    );
  }
}
