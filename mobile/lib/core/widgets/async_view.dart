import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// Renders [value]: a centered spinner while loading, the error text on
/// failure, otherwise [data]. Keeps showing previous data while
/// refreshing, so live updates never flash a spinner.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data});

  final AsyncValue<T> value;
  final Widget Function(T value) data;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) return data(value.requireValue);
    if (value.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text('${value.error}', textAlign: TextAlign.center, style: AppText.s(13, color: AppColors.danger)),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator(color: AppColors.primary));
  }
}
