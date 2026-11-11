import 'package:flutter/widgets.dart';

abstract final class AppSpacing {
  static const page = 20.0;
  static const gap = 12.0;
  static const pagePadding = EdgeInsets.symmetric(horizontal: page);
}

abstract final class AppRadius {
  static const card = 16.0;
  static const cardLg = 20.0;
  static const input = 12.0;
  static const button = 14.0;
  static const chip = 999.0;

  static const cardR = BorderRadius.all(Radius.circular(card));
  static const inputR = BorderRadius.all(Radius.circular(input));
  static const buttonR = BorderRadius.all(Radius.circular(button));
  static const chipR = BorderRadius.all(Radius.circular(chip));
}

abstract final class AppSizes {
  static const touch = 44.0;
  static const primaryButton = 56.0;
  static const button = 54.0;
  static const input = 48.0;
  static const bottomNav = 76.0;
}
