import 'package:intl/intl.dart';

const _digits = ['၀', '၁', '၂', '၃', '၄', '၅', '၆', '၇', '၈', '၉'];

/// 3 -> "၃"
String mmDigits(Object n) => n.toString().split('').map((c) {
      final d = int.tryParse(c);
      return d == null ? c : _digits[d];
    }).join();

const mmMonths = [
  'ဇန်နဝါရီ', 'ဖေဖော်ဝါရီ', 'မတ်', 'ဧပြီ', 'မေ', 'ဇွန်',
  'ဇူလိုင်', 'ဩဂုတ်', 'စက်တင်ဘာ', 'အောက်တိုဘာ', 'နိုဝင်ဘာ', 'ဒီဇင်ဘာ',
];

const mmMonthsShort = ['ဇန်', 'ဖေ', 'မတ်', 'ဧ', 'မေ', 'ဇွန်', 'ဇူ', 'ဩ', 'စက်', 'အောက်', 'နို', 'ဒီ'];

/// "4:05 PM" (local time).
String timeLabel(DateTime t) => DateFormat('h:mm a', 'en_US').format(t.toLocal());

/// Whole calendar days between [t] and [now] in local time.
int daysAgo(DateTime t, DateTime now) {
  final a = t.toLocal(), b = now.toLocal();
  return DateTime(b.year, b.month, b.day).difference(DateTime(a.year, a.month, a.day)).inDays;
}

/// "ယနေ့" or "နို ၇".
String dayLabel(DateTime t, DateTime now) {
  if (daysAgo(t, now) == 0) return 'ယနေ့';
  final l = t.toLocal();
  return '${mmMonthsShort[l.month - 1]} ${mmDigits(l.day)}';
}

/// Debt history date: "ယခုလေးတင်" / "ယနေ့ 2:58 PM" / "နို ၇ · 10:12 AM".
String entryDateLabel(DateTime t, DateTime now) {
  if (now.difference(t).inMinutes.abs() < 1) return 'ယခုလေးတင်';
  final d = dayLabel(t, now);
  return d == 'ယနေ့' ? '$d ${timeLabel(t)}' : '$d · ${timeLabel(t)}';
}

/// "ယနေ့" / "မနေ့က" / "၅ ရက်အရင်" / "၂ ပတ်အရင်" (14–27 days).
String agoLabel(DateTime t, DateTime now) {
  final d = daysAgo(t, now);
  if (d <= 0) return 'ယနေ့';
  if (d == 1) return 'မနေ့က';
  if (d >= 14 && d < 28) return '${mmDigits(d ~/ 7)} ပတ်အရင်';
  return '${mmDigits(d)} ရက်အရင်';
}

/// "၁၀ နိုဝင်ဘာ ၂၀၂၆ · 4:05 PM"
String mmReceiptDate(DateTime t) {
  final d = t.toLocal();
  return '${mmDigits(d.day)} ${mmMonths[d.month - 1]} ${mmDigits(d.year)} · ${timeLabel(d)}';
}
