import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/features/shop_template.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/digit_input.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/auth_controller.dart';
import '../data/auth_api.dart';
import '../data/session.dart';
import 'widgets/auth_message.dart';
import 'widgets/phone_field.dart';
import 'widgets/pin_entry.dart';

enum GoogleShopPurpose { signIn, reset }

/// docs/backend/auth-google.md §5.
/// [GoogleShopPurpose.signIn] (new phone): Google → choose the shop → its PIN. With no shop: open a
/// new one, or link a shop registered by phone before Google (phone + PIN, once).
/// [GoogleShopPurpose.reset] (forgot PIN; also while locked): Google → the shop (this phone's shop,
/// or the only one, is chosen for you) → new PIN twice.
/// Success changes the auth status; the router then leaves this screen.
class GoogleShopScreen extends ConsumerStatefulWidget {
  const GoogleShopScreen({super.key, this.purpose = GoogleShopPurpose.signIn});

  final GoogleShopPurpose purpose;

  @override
  ConsumerState<GoogleShopScreen> createState() => _GoogleShopScreenState();
}

class _GoogleShopScreenState extends ConsumerState<GoogleShopScreen> {
  GoogleShop? _shop;
  bool _linking = false;
  String _pin = '';

  /// Reset: the first entry, while [_pin] takes the confirmation.
  String? _firstPin;
  final _phone = TextEditingController();
  final _linkPin = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _reset => widget.purpose == GoogleShopPurpose.reset;

  @override
  void initState() {
    super.initState();
    final flow = ref.read(googleFlowProvider);
    if (flow != null) _shop = _preselect(flow.shops);
  }

  @override
  void dispose() {
    _phone.dispose();
    _linkPin.dispose();
    super.dispose();
  }

  /// The only shop, or (reset) the shop this phone already holds.
  GoogleShop? _preselect(List<GoogleShop> shops) {
    if (shops.length == 1) return shops.single;
    if (_reset) {
      final local = ref.read(sessionProvider).tenantId;
      for (final s in shops) {
        if (s.tenantId == local) return s;
      }
    }
    return null;
  }

  Future<void> _run(Future<void> Function(AuthController c) action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(authControllerProvider.notifier));
    } on AuthFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _pin = '';
          _firstPin = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() => _run((c) async {
        final flow = await c.googleSignIn();
        if (mounted) {
          setState(() {
            _shop = _preselect(flow.shops);
            _linking = false;
          });
        }
      });

  void _otherAccount() {
    ref.read(googleFlowProvider.notifier).set(null);
    setState(() {
      _shop = null;
      _linking = false;
      _pin = '';
      _firstPin = null;
      _error = null;
    });
    _google();
  }

  void _back() {
    if (_linking || (_shop != null && (ref.read(googleFlowProvider)?.shops.length ?? 0) > 1)) {
      setState(() {
        _linking = false;
        _shop = null;
        _pin = '';
        _firstPin = null;
        _error = null;
      });
    } else if (context.canPop()) {
      context.pop();
    } else {
      final locked = ref.read(authControllerProvider).status == AuthStatus.locked;
      context.go(locked ? Routes.unlock : Routes.login);
    }
  }

  Future<void> _submitPin() async {
    final shop = _shop!;
    if (_pin.length != 6) return setState(() => _error = AuthMessages.badPin);
    if (!_reset) return _run((c) => c.signInToShop(shop.tenantId, _pin));
    if (_firstPin == null) {
      setState(() {
        _firstPin = _pin;
        _pin = '';
        _error = null;
      });
      return;
    }
    if (_firstPin != _pin) {
      setState(() {
        _error = 'PIN အသစ် နှစ်ခါ မတူပါ။';
        _pin = '';
        _firstPin = null;
      });
      return;
    }
    await _run((c) => c.resetPinWithGoogle(tenantId: shop.tenantId, newPin: _pin));
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(googleFlowProvider);
    // A dropped flow (expired Google token) shows the Google step again.
    final shop = flow == null ? null : _shop;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(title: _reset ? 'PIN အသစ် သတ်မှတ်မယ်' : 'ဆိုင်ကို ဝင်မယ်', onBack: _back),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + bottom),
              children: [
                if (flow == null)
                  ..._googleStep()
                else ...[
                  _account(flow),
                  const SizedBox(height: 18),
                  if (_linking)
                    ..._linkStep()
                  else if (shop != null)
                    ..._pinStep(shop)
                  else if (flow.shops.isEmpty)
                    ..._noShop()
                  else
                    ..._shopList(flow.shops),
                ],
                if (_error != null) ...[const SizedBox(height: 16), AuthMessage(_error!)],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _googleStep() => [
        Text(
          _reset
              ? 'ဆိုင်ဖွင့်တုန်းက Google အကောင့်နဲ့ အတည်ပြုပြီး PIN အသစ် သတ်မှတ်ပါ။ PIN ပြောင်းရင် ဒီဆိုင်က တခြားဖုန်းတွေမှာလည်း PIN အသစ်နဲ့ ပြန်ဝင်ရပါမယ်။'
              : 'ဆိုင်ဖွင့်တုန်းက သုံးခဲ့တဲ့ Google အကောင့်ကို ရွေးပါ။',
          style: AppText.s(14, color: AppColors.muted),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: _busy ? 'ခဏစောင့်ပါ…' : (_reset ? 'Google နဲ့ အတည်ပြုမယ်' : 'Google နဲ့ ဝင်မယ်'),
          onPressed: _busy ? null : _google,
        ),
      ];

  Widget _account(GoogleFlowState flow) => Row(
        children: [
          Expanded(
            child: Text(flow.email ?? 'Google အကောင့်',
                style: AppText.s(14, weight: AppText.w600), overflow: TextOverflow.ellipsis),
          ),
          TextButton(
            onPressed: _busy ? null : _otherAccount,
            child: Text('တခြားအကောင့်', style: AppText.s(13, weight: AppText.w600, color: AppColors.primary)),
          ),
        ],
      );

  List<Widget> _shopList(List<GoogleShop> shops) => [
        Semantics(header: true, child: Text('ဘယ်ဆိုင်ကို ဝင်မလဲ?', style: AppText.s(20, weight: AppText.w700))),
        const SizedBox(height: 12),
        for (final s in shops) ...[
          _shopCard(s),
          const SizedBox(height: 10),
        ],
        if (!_reset) ...[
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'ဆိုင်အသစ် ဖွင့်မယ်',
            variant: ButtonVariant.outlineDark,
            onPressed: _busy ? null : () => context.push(Routes.register),
          ),
        ],
      ];

  Widget _shopCard(GoogleShop s) {
    final t = ShopTemplate.byId(s.templateId);
    return Semantics(
      button: true,
      label: s.name,
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _busy ? null : () => setState(() => _shop = s),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                InitialAvatar(initial: t.initial, bg: t.tint, fg: AppColors.textStrong, size: 40, radius: 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: AppText.s(16, weight: AppText.w700)),
                      Text(t.label, style: AppText.s(13, color: AppColors.muted)),
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

  List<Widget> _pinStep(GoogleShop shop) => [
        _shopCard(shop),
        const SizedBox(height: 20),
        PinEntry(
          title: !_reset
              ? 'ဆိုင်ရဲ့ PIN ထည့်ပါ'
              : _firstPin == null
                  ? 'PIN အသစ် (၆ လုံး)'
                  : 'PIN အသစ် ထပ်ရိုက်ပါ',
          subtitle: !_reset ? 'အက်ပ် ဖွင့်တိုင်း ဝင်တဲ့ PIN ပါ' : null,
          pin: _pin,
          onChanged: (p) => setState(() => _pin = p),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: _busy
              ? 'ခဏစောင့်ပါ…'
              : !_reset
                  ? 'ဝင်မယ်'
                  : _firstPin == null
                      ? 'ဆက်သွားမယ်'
                      : 'PIN အသစ် သိမ်းမယ်',
          onPressed: _busy ? null : _submitPin,
        ),
        if (!_reset) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => context.push(Routes.pinReset),
            child: Text('PIN မေ့နေပါသလား?', style: AppText.s(13, weight: AppText.w600, color: AppColors.primary)),
          ),
        ],
      ];

  List<Widget> _noShop() => [
        Semantics(
          header: true,
          child: Text('ဒီ Google အကောင့်မှာ ဆိုင် မရှိသေးပါ', style: AppText.s(20, weight: AppText.w700)),
        ),
        const SizedBox(height: 6),
        Text(
          _reset
              ? 'ဆိုင်ဖွင့်တုန်းက Google အကောင့်ကို ရွေးပါ။'
              : 'ဆိုင်အသစ် ဖွင့်နိုင်ပါတယ်။ ဖုန်းနံပါတ်နဲ့ ဖွင့်ထားတဲ့ ဆိုင်ရှိရင် တစ်ခါ ချိတ်ပေးပါ။',
          style: AppText.s(14, color: AppColors.muted),
        ),
        if (!_reset) ...[
          const SizedBox(height: 20),
          PrimaryButton(label: 'ဆိုင်အသစ် ဖွင့်မယ်', onPressed: _busy ? null : () => context.push(Routes.register)),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'ဖုန်းနံပါတ်နဲ့ ဖွင့်ထားတဲ့ ဆိုင် ရှိတယ်',
            variant: ButtonVariant.outlineDark,
            onPressed: _busy ? null : () => setState(() => _linking = true),
          ),
        ],
      ];

  List<Widget> _linkStep() => [
        Semantics(header: true, child: Text('ဆိုင်ကို ချိတ်မယ်', style: AppText.s(20, weight: AppText.w700))),
        const SizedBox(height: 6),
        Text('ဆိုင်ဖွင့်တုန်းက ဖုန်းနံပါတ်နဲ့ PIN ကို တစ်ခါ ထည့်ပါ။ နောက်ပိုင်း ဒီ Google အကောင့်နဲ့ ဝင်လို့ရပါပြီ။',
            style: AppText.s(14, color: AppColors.muted)),
        const SizedBox(height: 18),
        LabeledField(label: 'ဖုန်းနံပါတ်', child: PhoneField(controller: _phone)),
        const SizedBox(height: 16),
        LabeledField(
          label: 'PIN နံပါတ် (၆ လုံး)',
          child: AppInput(
            controller: _linkPin,
            height: 52,
            radius: 14,
            fontSize: 16,
            horizontalPadding: 14,
            hint: '••••••',
            obscure: true,
            keyboardType: TextInputType.number,
            semanticLabel: 'PIN နံပါတ်',
            inputFormatters: digitInput(maxLength: 6),
          ),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: _busy ? 'ခဏစောင့်ပါ…' : 'ချိတ်ပြီး ဝင်မယ်',
          onPressed: _busy ? null : () => _run((c) => c.linkPhoneShop(_phone.text, _linkPin.text)),
        ),
      ];
}
