import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_config.dart';
import '../api/api_error.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// How a text field treats non-ASCII characters (server `NonAsciiRule`).
enum NonAscii { allow, reject, drop }

class TextRule {
  const TextRule({
    required this.maxLength,
    this.required = true,
    this.allowEmpty = false,
    this.myanmarDigitsToAscii = false,
    this.nonAscii = NonAscii.allow,
  });

  /// UTF-16 code units (= Dart `String.length` = SQL Server nvarchar length).
  final int maxLength;
  final bool required;
  final bool allowEmpty;
  final bool myanmarDigitsToAscii;
  final NonAscii nonAscii;

  factory TextRule.fromJson(Map<String, dynamic> j) => TextRule(
        maxLength: (j['maxLength'] as num).toInt(),
        required: j['required'] as bool? ?? true,
        allowEmpty: j['allowEmpty'] as bool? ?? false,
        myanmarDigitsToAscii: j['myanmarDigitsToAscii'] as bool? ?? false,
        nonAscii: NonAscii.values.byName(j['nonAscii'] as String? ?? 'allow'),
      );
}

class NumberRule {
  const NumberRule({this.min, this.max});
  final int? min;
  final int? max;

  factory NumberRule.fromJson(Map<String, dynamic> j) =>
      NumberRule(min: (j['min'] as num?)?.toInt(), max: (j['max'] as num?)?.toInt());
}

/// `GET /api/v1/sync/limits`: every rule the server's push validator applies
/// (docs/mobile/phase3-sync.md §1.5). Forms check with the same rules, so the
/// server never rejects data the app accepted. Keys are wire names
/// (`products.name`).
class SyncLimitsData {
  const SyncLimitsData({required this.text, required this.numbers, this.json});

  final Map<String, TextRule> text;
  final Map<String, NumberRule> numbers;

  /// The JSON this was parsed from (cached in syncState).
  final String? json;

  factory SyncLimitsData.parse(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    return SyncLimitsData(
      text: {
        for (final e in (j['text'] as Map<String, dynamic>).entries)
          e.key: TextRule.fromJson((e.value as Map).cast<String, dynamic>()),
      },
      numbers: {
        for (final e in (j['numbers'] as Map<String, dynamic>).entries)
          e.key: NumberRule.fromJson((e.value as Map).cast<String, dynamic>()),
      },
      json: json,
    );
  }

  /// No rules (only for tests that don't exercise validation).
  static const none = SyncLimitsData(text: {}, numbers: {});

  /// [value] as the server will store it: Myanmar digits → 0-9 and dropped
  /// non-ASCII where the field says so; surrounding spaces trimmed.
  String normalize(String field, String value) {
    final rule = text[field];
    var v = value.trim();
    if (rule == null) return v;
    if (rule.myanmarDigitsToAscii) v = myanmarDigitsToAscii(v);
    if (rule.nonAscii == NonAscii.drop) v = String.fromCharCodes(v.codeUnits.where((c) => c < 128)).trim();
    return v;
  }

  /// Burmese error for [value] of text [field] (after [normalize]), or null if
  /// the server will accept it. [label] names the field in the message. A
  /// null/empty optional value is fine (the app sends null).
  String? checkText(String field, String? value, {required String label}) {
    final rule = text[field];
    if (rule == null) return null;
    final v = value == null ? null : normalize(field, value);
    if (v == null || v.isEmpty) {
      if (!rule.required) return null;
      return rule.allowEmpty && v != null ? null : '$label ထည့်ပါ။';
    }
    if (v.length > rule.maxLength) return '$label စာလုံး ${mmNumber(rule.maxLength)} လုံးထက် မပိုရပါ။';
    if (rule.nonAscii == NonAscii.reject && v.codeUnits.any((c) => c >= 128)) {
      return '$label မှာ ဂဏန်းနဲ့ အင်္ဂလိပ်စာလုံးပဲ ထည့်ပါ။';
    }
    return null;
  }

  /// Burmese error for [value] of number [field], or null.
  String? checkNumber(String field, int? value, {required String label}) {
    final rule = numbers[field];
    if (rule == null || value == null) return null;
    if (rule.min != null && value < rule.min!) return '$label ${mmNumber(rule.min!)} ထက် မနည်းရပါ။';
    if (rule.max != null && value > rule.max!) return '$label ${mmNumber(rule.max!)} ထက် မများရပါ။';
    return null;
  }
}

/// ၀-၉ → 0-9 (the server's `SyncText.AsciiDigits`).
String myanmarDigitsToAscii(String s) =>
    s.replaceAllMapped(RegExp('[၀-၉]'), (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0x1040 + 0x30));

/// syncState keys of the cached copy (§3.2).
abstract final class LimitsKeys {
  static const json = 'limitsJson';
}

const bundledLimitsAsset = 'assets/sync/limits.json';

/// At launch: the cached server copy if any, else the bundled copy (same values
/// as the server at build time). Never needs the network.
Future<SyncLimitsData> loadLimits(AppDatabase db) async {
  final cached = await db.readState(LimitsKeys.json);
  if (cached != null) {
    try {
      return SyncLimitsData.parse(cached);
    } on Object {
      // A broken cache falls back to the bundled copy.
    }
  }
  return SyncLimitsData.parse(await rootBundle.loadString(bundledLimitsAsset));
}

/// Bound in main.dart from [loadLimits].
final initialLimitsProvider = Provider<SyncLimitsData>((_) => SyncLimitsData.none);

class SyncLimitsNotifier extends Notifier<SyncLimitsData> {
  @override
  SyncLimitsData build() => ref.watch(initialLimitsProvider);

  /// `GET /sync/limits` (anonymous) → cached and used from now on. Errors are
  /// ignored: the current rules stay.
  Future<void> refresh() async {
    try {
      final r = await Dio(BaseOptions(baseUrl: ref.read(apiBaseUrlProvider), responseType: ResponseType.plain))
          .get<String>('/api/v1/sync/limits');
      final body = r.data;
      if (body == null) return;
      final limits = SyncLimitsData.parse(body);
      if (limits.text.isEmpty) return;
      await ref.read(appDatabaseProvider).writeState(LimitsKeys.json, body);
      state = limits;
    } on DioException {
      // offline: keep the cached/bundled rules
    } on ApiError {
      // same
    } on FormatException {
      // unexpected body: keep the current rules
    }
  }
}

final syncLimitsProvider = NotifierProvider<SyncLimitsNotifier, SyncLimitsData>(SyncLimitsNotifier.new);
