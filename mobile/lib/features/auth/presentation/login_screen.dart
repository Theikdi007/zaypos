import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/primary_button.dart';
import 'widgets/phone_field.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                      const SizedBox(height: 28),
                      _form(context),
                      const SizedBox(height: 28),
                      _orDivider(),
                      const SizedBox(height: 28),
                      PrimaryButton(
                        label: 'ဆိုင်အသစ် စာရင်းသွင်းမယ်',
                        variant: ButtonVariant.outlineDark,
                        height: 54,
                        radius: 14,
                        fontSize: 15,
                        onPressed: () => context.push(Routes.register),
                      ),
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

  Widget _form(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LabeledField(label: 'ဖုန်းနံပါတ်', child: PhoneField()),
        const SizedBox(height: 16),
        LabeledField(
          label: 'PIN နံပါတ် (၆ လုံး)',
          child: AppInput(
            height: 52,
            radius: 14,
            fontSize: 16,
            horizontalPadding: 14,
            hint: '••••••',
            obscure: true,
            keyboardType: TextInputType.number,
            semanticLabel: 'PIN နံပါတ်',
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: InkWell(
            onTap: () {},
            child: Text('PIN မေ့နေပါသလား?',
                style: AppText.s(13, weight: AppText.w600, color: AppColors.primary)),
          ),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'ဝင်မယ်',
          height: 54,
          radius: 14,
          onPressed: () => context.go(Routes.dashboard),
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
