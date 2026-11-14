import 'package:flutter/material.dart';

/// A [ListTile] for use inside [AppCard] (a coloured container): it brings
/// its own transparent [Material], so ink splashes show and Flutter's
/// "ListTile background color or ink splashes may be invisible" check passes.
class CardListTile extends StatelessWidget {
  const CardListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isThreeLine = false,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isThreeLine;

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: ListTile(
          title: title,
          subtitle: subtitle,
          trailing: trailing,
          onTap: onTap,
          isThreeLine: isThreeLine,
        ),
      );
}
