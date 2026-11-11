/// A till/phone that issues receipts. Each device has its own short code
/// ('A', 'B', …) and its own sequence, so receipt numbers created offline on
/// different devices never collide ("A-1033" vs "B-1033").
class Device {
  const Device({
    required this.id,
    required this.tenantId,
    required this.code,
    required this.lastSeq,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String tenantId;

  /// Short per-tenant code: 'A', 'B', …
  final String code;

  /// Last receipt sequence issued by this device (0 = none yet).
  final int lastSeq;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// Receipt number the next sale will get.
  String get nextReceiptNo => formatReceiptNo(code, lastSeq + 1);

  Device copyWith({int? lastSeq, DateTime? updatedAt, DateTime? Function()? deletedAt}) => Device(
        id: id,
        tenantId: tenantId,
        code: code,
        lastSeq: lastSeq ?? this.lastSeq,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );
}

/// ("A", 1033) -> "A-1033"; ("A", 987) -> "A-0987".
String formatReceiptNo(String code, int seq) => '$code-${seq.toString().padLeft(4, '0')}';
