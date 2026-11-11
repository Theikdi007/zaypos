import 'package:intl/intl.dart';

/// Money is always `int` kyats (Myanmar has no subunit in practice).
final _fmt = NumberFormat('#,##0', 'en_US');

/// 245800 -> "245,800"
String formatMoney(int kyats) => _fmt.format(kyats);

/// 245800 -> "245,800 Ks"
String formatKs(int kyats) => '${formatMoney(kyats)} Ks';
