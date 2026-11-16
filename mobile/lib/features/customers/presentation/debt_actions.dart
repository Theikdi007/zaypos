import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/money_format.dart';
import '../../../core/utils/myanmar.dart';
import '../../../core/utils/phone.dart';

/// BUG-46: the debtor screen's "ဖုန်းခေါ်ရန်" and "Viber သတိပေး".

const debtCallLabel = 'ဖုန်းခေါ်ရန်';
const debtRemindLabel = 'Viber သတိပေး';
const debtNoPhoneHint = 'ဖုန်းနံပါတ် မရှိလို့ ခေါ်လို့ မရပါ';
const debtCallFailedText = 'ဖုန်းခေါ်လို့ မရပါ။';
const debtRemindFailedText = 'သတိပေးစာ ပို့လို့ မရပါ။ ထပ်ကြိုးစားပါ။';

/// The `tel:` link for a stored customer phone, or null when there is no number.
/// Myanmar digits become 0-9 and spaces/dashes/dots/brackets are dropped
/// ("၀၉ ၇၉၀-၀၁၁ ၀၀၂" → tel:09790011002).
Uri? telUri(String? phone) {
  final digits = phoneKey(phone).replaceAll(RegExp(r'[^0-9+]'), '');
  if (RegExp(r'\d').allMatches(digits).length < 3) return null;
  return Uri(scheme: 'tel', path: digits);
}

/// "၁၅ နိုဝင်ဘာ ၂၀၂၆" (no time).
String mmLongDate(DateTime t) {
  final d = t.toLocal();
  return '${mmDigits(d.day)} ${mmMonths[d.month - 1]} ${mmDigits(d.year)}';
}

/// BUG-47: "Viber သတိပေး" is shown only to a customer who owes something.
bool showDebtReminder(int balance) => balance > 0;

/// The reminder that "Viber သတိပေး" puts into the share sheet.
String debtReminderText({
  required String shop,
  required String customer,
  required int balance,
  required DateTime date,
}) =>
    'မင်္ဂလာပါ $customer\n'
    '$shop မှ အကြွေး သတိပေးစာ ဖြစ်ပါတယ်။\n'
    '${mmLongDate(date)} နေ့အထိ ပေးရန်ကျန်ငွေ ${formatKs(balance)} ရှိပါတယ်။\n'
    'အဆင်ပြေတဲ့အချိန် ပေးချေပေးပါ။ ကျေးဇူးတင်ပါတယ်။';

/// Where the two actions go: the dialer and the share sheet. Tests replace it.
abstract class DebtOutlet {
  /// Opens the phone app with [uri]. False when it could not be opened.
  Future<bool> call(Uri uri);

  /// Opens the system share sheet with [text] (Viber is one of the targets).
  Future<void> shareText(String text, {Rect? origin});
}

class PlatformDebtOutlet implements DebtOutlet {
  const PlatformDebtOutlet();

  @override
  Future<bool> call(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> shareText(String text, {Rect? origin}) =>
      SharePlus.instance.share(ShareParams(text: text, sharePositionOrigin: origin));
}

final debtOutletProvider = Provider<DebtOutlet>((_) => const PlatformDebtOutlet());
