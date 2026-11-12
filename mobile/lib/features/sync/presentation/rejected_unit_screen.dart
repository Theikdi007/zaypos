import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/sync/sync_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/presentation/widgets/auth_message.dart';
import '../domain/sync_labels.dart';

/// One rejected unit (§7): what it was, the server's reason, and two ways
/// out — fix the data and send again, or send it to support. There is no
/// delete: nothing in the outbox is ever dropped.
class RejectedUnitScreen extends ConsumerStatefulWidget {
  const RejectedUnitScreen({super.key, required this.seq});
  final int seq;

  @override
  ConsumerState<RejectedUnitScreen> createState() => _RejectedUnitScreenState();
}

class _Field {
  _Field(this.table, this.id, this.column, String? value)
      : original = value,
        controller = TextEditingController(text: value ?? '');
  final String table;
  final String id;
  final String column;
  final String? original;
  final TextEditingController controller;
}

class _RejectedUnitScreenState extends ConsumerState<RejectedUnitScreen> {
  List<_Field>? _fields;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final f in _fields ?? const <_Field>[]) {
      f.controller.dispose();
    }
    super.dispose();
  }

  List<_Field> _fieldsOf(Map<String, dynamic> rows) => [
        for (final MapEntry(key: table, value: list) in rows.entries)
          for (final r in list as List)
            for (final col in editableColumns[table] ?? const <String>[])
              if ((r as Map).containsKey(col) && r['id'] is String) _Field(table, r['id'] as String, col, r[col] as String?),
      ];

  UnitEdits _edits() {
    final out = <String, Map<String, Map<String, String?>>>{};
    for (final f in _fields ?? const <_Field>[]) {
      final text = f.controller.text.trim();
      // Untouched = same text ('' and null count as equal). A cleared field
      // stays '' unless it was null before: required columns are NOT NULL.
      if (text == (f.original ?? '')) continue;
      ((out[f.table] ??= {})[f.id] ??= {})[f.column] = text.isEmpty && f.original == null ? null : text;
    }
    return out;
  }

  Future<void> _resend() async {
    final engine = ref.read(syncEngineProvider);
    final store = engine.store;
    if (store == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await store.resend(widget.seq, edits: _edits());
      unawaited(engine.syncNow(manual: true));
      if (mounted) context.pop();
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'ပြန်ပို့လို့ မရပါ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyForSupport(OutboxRow o) async {
    final json = const JsonEncoder.withIndent('  ').convert({
      'unitId': o.unitId,
      'kind': o.kind,
      'clientTime': DateTime.fromMillisecondsSinceEpoch(o.clientTime, isUtc: true).toIso8601String(),
      'rejectReason': o.rejectReason,
      'rows': SyncStore.rowsOf(o),
    });
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copy ကူးပြီးပါပြီ။ Viber မှာ Support ကို paste လုပ်ပြီး ပို့ပေးပါ။')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final units = ref.watch(rejectedUnitsProvider).value;
    final o = units?.where((u) => u.seq == widget.seq).firstOrNull;
    if (o == null) {
      return Scaffold(
        body: Column(children: [
          ScreenHeader(title: 'စစ်ရန်', onBack: () => context.pop()),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(units == null ? '' : 'ဒီစာရင်း ပြန်ပို့ပြီးပါပြီ။', style: AppText.s(14, color: AppColors.muted)),
          ),
        ]),
      );
    }
    final rows = SyncStore.rowsOf(o);
    _fields ??= _fieldsOf(rows);
    final fields = _fields!;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(title: 'လက်မခံသေးတဲ့ စာရင်း', onBack: () => context.pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Semantics(header: true, child: Text(unitSummary(o.kind, rows), style: AppText.s(17, weight: AppText.w700))),
                const SizedBox(height: 12),
                Text('Server ရဲ့ အကြောင်းပြချက်', style: AppText.s(13, weight: AppText.w600)),
                const SizedBox(height: 6),
                AuthMessage(o.rejectReason ?? ''),
                const SizedBox(height: 20),
                if (fields.isNotEmpty) ...[
                  Text('ပြင်ရန်', style: AppText.s(13, weight: AppText.w600)),
                  const SizedBox(height: 6),
                  for (final f in fields) ...[
                    LabeledField(
                      label: '${fieldLabel(f.column)} · ${f.table}',
                      child: AppInput(controller: f.controller, height: 46, semanticLabel: fieldLabel(f.column)),
                    ),
                    const SizedBox(height: 10),
                  ],
                ] else
                  Text('ဒီစာရင်းမှာ ပြင်စရာ စာသား မရှိပါ။ App update ပြီးရင် ပြန်ပို့ကြည့်ပါ (သို့) Support ကို ပို့ပါ။',
                      style: AppText.s(13, color: AppColors.muted)),
                if (_error != null) ...[const SizedBox(height: 8), AuthMessage(_error!)],
                const SizedBox(height: 16),
                PrimaryButton(label: 'ပြင်ပြီး ပြန်ပို့မယ်', onPressed: _busy ? null : _resend),
                const SizedBox(height: 10),
                PrimaryButton(
                  label: 'Support ကို ပို့မယ်',
                  variant: ButtonVariant.outlineDark,
                  onPressed: _busy ? null : () => _copyForSupport(o),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
