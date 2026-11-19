import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_config.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/auth_controller.dart';
import 'widgets/auth_message.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

/// Signed out: Google → choose the shop → PIN (docs/backend/auth-google.md §5). There is no phone + PIN
/// sign-in: the PIN only unlocks a phone that is already signed in (or is checked together with Google).
class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _busy = false;
  String? _error;

  /// Runs [action]; failures show as a message. Success changes the auth
  /// status, and the router guard moves on to the app.
  Future<void> _run(Future<void> Function(AuthController c) action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(authControllerProvider.notifier));
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notice = ref.watch(authControllerProvider.select((s) => s.notice));
    final showDemo = !ref.watch(isReleaseBuildProvider);
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 72, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _brand(),
                      if (notice != null) ...[
                        const SizedBox(height: 20),
                        AuthMessage(notice, isError: false),
                      ],
                      const SizedBox(height: 28),
                      _googleForm(context),
                      const SizedBox(height: 28),
                      _orDivider(),
                      const SizedBox(height: 28),
                      PrimaryButton(
                        label: 'ဆိုင်အသစ် စာရင်းသွင်းမယ်',
                        variant: ButtonVariant.outlineDark,
                        height: 54,
                        radius: 14,
                        fontSize: 15,
                        onPressed: _busy ? null : () => context.push(Routes.register),
                      ),
                      if (showDemo) ...[
                        const SizedBox(height: 12),
                        // Debug builds only: the offline sample shop (never synced).
                        PrimaryButton(
                          label: 'စမ်းသပ်ဆိုင် (အင်တာနက်မလို)',
                          variant: ButtonVariant.outlineDark,
                          height: 46,
                          radius: 14,
                          fontSize: 14,
                          onPressed: _busy ? null : () => _run((c) => c.openDemo()),
                        ),
                      ],
                      const SizedBox(height: 28),
                      const Spacer(),
                      _offlineNote(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _brand() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(18)),
          alignment: Alignment.center,
          child: const AppIcon(AppIcons.store, size: 34, color: AppColors.surface),
        ),
        const SizedBox(height: 16),
        Text('ZayPOS', style: AppText.s(28, weight: AppText.w700, letterSpacing: -0.5)),
        const SizedBox(height: 4),
        Text('ဆိုင်စာရင်းကို ဖုန်းတစ်လုံးနဲ့ လွယ်လွယ်ကူကူ စီမံပါ',
            style: AppText.s(15, color: AppColors.muted)),
      ],
    );
  }

  /// Default sign-in (docs/backend/auth-google.md §5): Google → choose the shop → PIN.
  Widget _googleForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('ဆိုင်ဖွင့်တုန်းက သုံးခဲ့တဲ့ Google အကောင့်နဲ့ ဝင်ပါ။', style: AppText.s(14, color: AppColors.muted)),
        if (_error != null) ...[
          const SizedBox(height: 12),
          AuthMessage(_error!),
        ],
        const SizedBox(height: 16),
        PrimaryButton(
          label: _busy ? 'ဝင်နေသည်…' : 'Google နဲ့ ဝင်မယ်',
          height: 54,
          radius: 14,
          onPressed: _busy
              ? null
              : () => _run((c) async {
                    await c.googleSignIn();
                    if (context.mounted) await context.push(Routes.chooseShop);
                  }),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: InkWell(
            onTap: _busy ? null : () => context.push(Routes.pinReset),
            child: Text('PIN မေ့နေပါသလား?',
                style: AppText.s(13, weight: AppText.w600, color: AppColors.primary)),
          ),
        ),
      ],
    );
  }

  Widget _orDivider() {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: AppColors.border)),
        const SizedBox(width: 12),
        Text('သို့မဟုတ်', style: AppText.s(13, color: AppColors.muted)),
        const SizedBox(width: 12),
        Expanded(child: Container(height: 1, color: AppColors.border)),
      ],
    );
  }

  Widget _offlineNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: AppIcon(AppIcons.shield, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'အင်တာနက်မရှိလည်း ရောင်းလို့ရပါတယ်။ လိုင်းပြန်ရတာနဲ့ အလိုအလျောက် sync လုပ်ပေးပါမယ်။',
              style: AppText.s(13, color: AppColors.primaryInk),
            ),
          ),
        ],
      ),
    );
  }
}
