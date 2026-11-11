import 'package:flutter/material.dart';

/// All colors used in the ZayPOS design. Widgets must reference these,
/// never raw hex values.
abstract final class AppColors {
  // Core tokens (handoff note)
  static const primary = Color(0xFF0F766E);
  static const primaryHover = Color(0xFF115E59);
  static const ground = Color(0xFFF4F6F5);
  static const surface = Color(0xFFFFFFFF);
  static const text = Color(0xFF111827);
  static const muted = Color(0xFF4B5563);
  static const border = Color(0xFFE5E7EB);
  static const debt = Color(0xFFC2410C);
  static const debtBg = Color(0xFFFFF7ED);
  static const success = Color(0xFF065F46);
  static const successBg = Color(0xFFECFDF5);
  static const danger = Color(0xFFB91C1C);

  // Neutrals
  static const divider = Color(0xFFEEF0EF);
  static const inputBorder = Color(0xFFD1D5DB);
  static const fill = Color(0xFFF3F4F6); // search / segmented / keys
  static const fillSoft = Color(0xFFF9FAFB);
  static const textStrong = Color(0xFF1F2937);
  static const textSecondary = Color(0xFF374151);
  static const textDisabled = Color(0xFF6B7280);
  static const subtle = Color(0xFF9CA3AF); // switch off, dashed borders
  static const scrim = Color(0x59111827); // rgba(17,24,39,0.35)
  static const knobShadow = Color(0x40000000);
  static const fabShadow = Color(0x4D0F766E);
  static const onPrimaryOverlay = Color(0x2EFFFFFF); // rgba(255,255,255,0.18)

  // Primary family
  static const primarySoft = Color(0xFFF0FDF9); // selected bg
  static const primaryInk = Color(0xFF134E4A); // info text
  static const chartBar = Color(0xFF99D5CC);

  // Warm / debt family
  static const debtInk = Color(0xFF9A3412);
  static const debtAvatar = Color(0xFFFED7AA);
  static const debtAvatarSoft = Color(0xFFFFEDD5);
  static const debtBorder = Color(0xFFFDBA74);
  static const offlineBg = Color(0xFFFFF4E5);

  // Danger family
  static const dangerBg = Color(0xFFFEE2E2);
  static const dangerInk = Color(0xFF991B1B);

  // Payment methods
  static const payCash = Color(0xFF16A34A);
  static const payKbz = Color(0xFF1D4ED8);
  static const payWave = Color(0xFFCA8A04);
  static const payDebt = debt;

  // Template / product tints
  static const tintGreen = Color(0xFFDCFCE7);
  static const tintBlue = Color(0xFFDBEAFE);
  static const tintIndigo = Color(0xFFE0E7FF);
  static const tintPink = Color(0xFFFCE7F3);
  static const tintAmber = Color(0xFFFEF3C7);
  static const tintOrange = Color(0xFFFFEDD5);
  static const tintRed = Color(0xFFFEE2E2);
  static const tintGray = Color(0xFFF3F4F6);
  static const tintGrayMid = Color(0xFFE5E7EB);
  static const tintYellow = Color(0xFFFDE68A);

  // Feature section borders (Add Product)
  static const pharmacyBorder = Color(0xFFBFDBFE);
  static const phoneBorder = Color(0xFFC7D2FE);
  static const fashionBorder = Color(0xFFFBCFE8);
  static const serialChipBg = Color(0xFFEEF2FF);
  static const serialChipFg = Color(0xFF3730A3);
  static const fashionSelBg = Color(0xFFFDF2F8);
  static const fashionSelBorder = Color(0xFFDB2777);

  // Swatches
  static const swatchBlack = Color(0xFF111827);
  static const swatchWhite = Color(0xFFFFFFFF);
  static const swatchBlue = Color(0xFF2563EB);
  static const swatchRed = Color(0xFFDC2626);

  static const transparent = Color(0x00000000);
}
