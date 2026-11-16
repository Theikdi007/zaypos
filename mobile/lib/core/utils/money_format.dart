import 'package:intl/intl.dart';

/// Money is always `int` kyats (Myanmar has no subunit in practice).
final _fmt = NumberFormat('#,##0', 'en_US');

/// 245800 -> "245,800"
String formatMoney(int kyats) => _fmt.format(kyats);

/// 245800 -> "245,800 Ks"
String formatKs(int kyats) => '${formatMoney(kyats)} Ks';

/// Shown instead of a profit when the cost was never entered (BUG-53).
const costUnknownLabel = 'အရင်းမသိ';

/// A profit total (lines with no cost already left out):
/// "1,500 Ks", or "အရင်းမသိ" when not one sold line had a cost.
String formatProfit(int profit, {required bool unknown}) => unknown ? costUnknownLabel : formatKs(profit);

/// Small note under a profit total: "အရင်းမသိ 3 ခု မပါ" (null when 0).
String? unknownCostNote(int unknownLines) => unknownLines > 0 ? '$costUnknownLabel $unknownLines ခု မပါ' : null;
