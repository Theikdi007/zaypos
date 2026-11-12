import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/numeric_keypad.dart';
import '../application/auth_controller.dart';
import '../data/session.dart';
import 'widgets/auth_message.dart';

/// Opens a stored session with the 6-digit PIN, offline (§6). The PIN is
/// checked against the local PBKDF2 hash; 5 wrong PINs lock it for 15 minutes.
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  String _pin = '';
  bool _busy = false;
  String? _error;
  Timer? _lockTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_showLock());
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    super.dispose();
  }

  /// Shows a running lockout (and re-checks every 30 s until it ends).
  Future<void> _showLock() async {
    final left = await ref.read(authControllerProvider.notifier).lockRemaining();
    if (!mounted) return;
    setState(() => _error = left == null ? null : AuthMessages.locked(left));
    _lockTimer?.cancel();
    if (left != null) _lockTimer = Timer(const Duration(seconds: 30), _showLock);
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).unlock(_pin);
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _pin = '';
      });
      if (e.code == 'pin_locked') unawaited(_showLock());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onKey(String k) {
    if (_busy) return;
    setState(() {
      if (k == NumericKeypad.backspace) {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 6) {
        _pin += k;
      }
    });
    if (_pin.length == 6) unawaited(_submit());
  }

  @override
  Widget build(BuildContext context) {
    final shop = ref.watch(sessionProvider.select((s) => s.shopName));
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
                  alignment: Alignment.center,
                  child: const AppIcon(AppIcons.store, size: 30, color: AppColors.surface),
                ),
              ),
              const SizedBox(height: 14),
              Semantics(
                header: true,
                child: Text(shop, textAlign: TextAlign.center, style: AppText.s(20, weight: AppText.w700)),
              ),
              const SizedBox(height: 4),
              Text('PIN နံပါတ် ထည့်ပါ', textAlign: TextAlign.center, style: AppText.s(14, color: AppColors.muted)),
              const SizedBox(height: 20),
              Semantics(
                label: 'PIN ${_pin.length} / 6 လုံး',
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
                          color: i < _pin.length ? AppColors.text : AppColors.transparent,
                          border: Border.all(color: i < _pin.length ? AppColors.text : AppColors.subtle, width: 2),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null) AuthMessage(_error!) else const SizedBox(height: 8),
              const SizedBox(height: 16),
              NumericKeypad(
                keys: NumericKeypad.pinKeys,
                keyHeight: 60,
                gap: 10,
                radius: 14,
                keyColor: AppColors.fill,
                onKey: _onKey,
              ),
              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : () => ref.read(authControllerProvider.notifier).signOut(),
                  child: Text('တခြားအကောင့်နဲ့ ဝင်မယ်',
                      style: AppText.s(13, weight: AppText.w600, color: AppColors.primary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
