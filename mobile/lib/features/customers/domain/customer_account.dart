import 'customer.dart';
import 'debt_entry.dart';

/// Read model: a customer plus everything derived from their ledger.
class CustomerAccount {
  CustomerAccount(this.customer, List<DebtEntry> entries, {this.storedBalance})
      : entries = [...entries]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Days without activity after which an unpaid balance is "overdue".
  static const overdueDays = 30;

  final Customer customer;

  /// All live ledger entries, newest first.
  final List<DebtEntry> entries;

  String get id => customer.id;
  String get name => customer.name;
  String get initial => customer.initial;

  /// The database's SUM over the ledger; null = sum [entries] here.
  final int? storedBalance;

  /// Kyats owed (sum of ledger).
  int get balance => storedBalance ?? debtBalance(entries);
  bool get hasDebt => balance > 0;

  /// Entries shown in the history list (system void reversals hidden).
  List<DebtEntry> get history => entries.where((e) => !e.isSaleReversal).toList();

  DateTime get lastActivityAt => entries.isEmpty ? customer.createdAt : entries.first.createdAt;

  /// Ids of entries in this ledger (to find payment reversals).
  late final Set<String> _ids = {for (final e in entries) e.id};

  /// A payment that has been reversed (its reversal row is in the ledger).
  bool isReversed(DebtEntry e) => e.type == DebtEntryType.payment && _ids.contains(paymentReversalId(e.id));

  /// A payment that can still be reversed.
  bool canReverse(DebtEntry e) => e.type == DebtEntryType.payment && e.deletedAt == null && !isReversed(e);

  DateTime? get lastPaymentAt {
    for (final e in entries) {
      if (e.type == DebtEntryType.payment && !isReversed(e)) return e.createdAt;
    }
    return null;
  }

  bool isOverdue(DateTime now) => hasDebt && now.difference(lastActivityAt).inDays >= overdueDays;
}
