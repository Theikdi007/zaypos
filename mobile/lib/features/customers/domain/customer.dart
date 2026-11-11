/// Customer master data. The debt balance is NOT stored here — it is the
/// sum of the customer's [DebtEntry] ledger (see debt_entry.dart).
class Customer {
  const Customer({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.phone,
    required this.createdAt,
    required this.updatedAt,
    this.address,
    this.creditLimit,
    this.note,
    this.deletedAt,
  });

  final String id;
  final String tenantId;
  final String name;
  final String phone;
  final String? address;

  /// Kyats; null = no limit.
  final int? creditLimit;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// First code point — the leading consonant shown in the avatar.
  String get initial => name.isEmpty ? '' : String.fromCharCode(name.runes.first);

  Customer copyWith({
    String? name,
    String? phone,
    String? Function()? address,
    int? Function()? creditLimit,
    String? Function()? note,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) =>
      Customer(
        id: id,
        tenantId: tenantId,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        address: address != null ? address() : this.address,
        creditLimit: creditLimit != null ? creditLimit() : this.creditLimit,
        note: note != null ? note() : this.note,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );
}
