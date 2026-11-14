// Domain entity <-> Drift row. Pure functions, no I/O.

import '../../features/customers/domain/customer.dart';
import '../../features/customers/domain/debt_entry.dart';
import '../../features/devices/domain/device.dart';
import '../../features/inventory/domain/stock_movement.dart';
import '../../features/products/domain/product.dart';
import '../../features/products/domain/product_modules.dart';
import '../../features/sales/domain/sale.dart';
import 'app_database.dart';

// ---------------------------------------------------------------- products

ProductRow productRow(Product p) => ProductRow(
      id: p.id,
      tenantId: p.tenantId,
      name: p.name,
      category: p.category,
      unit: p.unit,
      barcode: p.barcode,
      cost: p.cost,
      price: p.price,
      wholesalePrice: p.wholesalePrice,
      lowAlertMilli: p.lowAlertMilli,
      warrantyMonths: p.warrantyMonths,
      expiryAlertDays: p.expiryAlertDays,
      tint: p.tint,
      initial: p.initial,
      createdAt: p.createdAt,
      updatedAt: p.updatedAt,
      deletedAt: p.deletedAt,
    );

Product productFromRow(ProductRow r) => Product(
      id: r.id,
      tenantId: r.tenantId,
      name: r.name,
      category: r.category,
      unit: r.unit,
      barcode: r.barcode,
      cost: r.cost,
      price: r.price,
      wholesalePrice: r.wholesalePrice,
      lowAlertMilli: r.lowAlertMilli,
      warrantyMonths: r.warrantyMonths,
      expiryAlertDays: r.expiryAlertDays,
      tint: r.tint,
      initial: r.initial,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      deletedAt: r.deletedAt,
    );

ProductVariantRow variantRow(ProductVariant v) => ProductVariantRow(
      id: v.id,
      tenantId: v.tenantId,
      productId: v.productId,
      size: v.size,
      color: v.color,
      createdAt: v.createdAt,
      updatedAt: v.updatedAt,
      deletedAt: v.deletedAt,
    );

ProductVariant variantFromRow(ProductVariantRow r) => ProductVariant(
      id: r.id,
      tenantId: r.tenantId,
      productId: r.productId,
      size: r.size,
      color: r.color,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      deletedAt: r.deletedAt,
    );

ProductBatchRow batchRow(ProductBatch b) => ProductBatchRow(
      id: b.id,
      tenantId: b.tenantId,
      productId: b.productId,
      batchNo: b.batchNo,
      expiryDate: b.expiryDate,
      createdAt: b.createdAt,
      updatedAt: b.updatedAt,
      deletedAt: b.deletedAt,
    );

/// [stockMilli] = sum of the batch's stock movements (derived, §3.3).
ProductBatch batchFromRow(ProductBatchRow r, int stockMilli) => ProductBatch(
      id: r.id,
      tenantId: r.tenantId,
      productId: r.productId,
      batchNo: r.batchNo,
      expiryDate: r.expiryDate,
      qtyMilli: stockMilli,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      deletedAt: r.deletedAt,
    );

ProductSerialRow serialRow(ProductSerial s) => ProductSerialRow(
      id: s.id,
      tenantId: s.tenantId,
      productId: s.productId,
      serial: s.serial,
      status: s.status,
      saleLineId: s.saleLineId,
      createdAt: s.createdAt,
      updatedAt: s.updatedAt,
      deletedAt: s.deletedAt,
    );

ProductSerial serialFromRow(ProductSerialRow r) => ProductSerial(
      id: r.id,
      tenantId: r.tenantId,
      productId: r.productId,
      serial: r.serial,
      status: r.status,
      saleLineId: r.saleLineId,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      deletedAt: r.deletedAt,
    );

// ---------------------------------------------------------------- stock

StockMovementRow movementRow(StockMovement m, {String? deviceId}) => StockMovementRow(
      id: m.id,
      tenantId: m.tenantId,
      productId: m.productId,
      variantId: m.variantId,
      batchId: m.batchId,
      type: m.type,
      qtyMilli: m.qtyMilli,
      saleId: m.saleId,
      note: m.note,
      deviceId: deviceId,
      createdAt: m.createdAt,
      updatedAt: m.updatedAt,
      deletedAt: m.deletedAt,
    );

StockMovement movementFromRow(StockMovementRow r) => StockMovement(
      id: r.id,
      tenantId: r.tenantId,
      productId: r.productId,
      variantId: r.variantId,
      batchId: r.batchId,
      type: r.type,
      qtyMilli: r.qtyMilli,
      saleId: r.saleId,
      note: r.note,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      deletedAt: r.deletedAt,
    );

// ---------------------------------------------------------------- customers

CustomerRow customerRow(Customer c) => CustomerRow(
      id: c.id,
      tenantId: c.tenantId,
      name: c.name,
      phone: c.phone,
      address: c.address,
      creditLimit: c.creditLimit,
      note: c.note,
      createdAt: c.createdAt,
      updatedAt: c.updatedAt,
      deletedAt: c.deletedAt,
    );

Customer customerFromRow(CustomerRow r) => Customer(
      id: r.id,
      tenantId: r.tenantId,
      name: r.name,
      phone: r.phone,
      address: r.address,
      creditLimit: r.creditLimit,
      note: r.note,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      deletedAt: r.deletedAt,
    );

DebtEntryRow debtRow(DebtEntry e, {String? deviceId}) => DebtEntryRow(
      id: e.id,
      tenantId: e.tenantId,
      customerId: e.customerId,
      type: e.type,
      amount: e.amount,
      saleId: e.saleId,
      saleNo: e.saleNo,
      method: e.method,
      note: e.note,
      deviceId: deviceId,
      createdAt: e.createdAt,
      updatedAt: e.updatedAt,
      deletedAt: e.deletedAt,
    );

DebtEntry debtFromRow(DebtEntryRow r) => DebtEntry(
      id: r.id,
      tenantId: r.tenantId,
      customerId: r.customerId,
      type: r.type,
      amount: r.amount,
      saleId: r.saleId,
      saleNo: r.saleNo,
      method: r.method,
      note: r.note,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      deletedAt: r.deletedAt,
    );

// ---------------------------------------------------------------- devices

DeviceRow deviceRow(Device d, {String? name, DateTime? lastSyncAt}) => DeviceRow(
      id: d.id,
      tenantId: d.tenantId,
      code: d.code,
      name: name,
      lastSeq: d.lastSeq,
      lastSyncAt: lastSyncAt,
      createdAt: d.createdAt,
      updatedAt: d.updatedAt,
      deletedAt: d.deletedAt,
    );

Device deviceFromRow(DeviceRow r) => Device(
      id: r.id,
      tenantId: r.tenantId,
      code: r.code,
      lastSeq: r.lastSeq,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      deletedAt: r.deletedAt,
    );

// ---------------------------------------------------------------- sales

SaleRow saleRow(Sale s, {String? deviceId}) => SaleRow(
      id: s.id,
      tenantId: s.tenantId,
      no: s.no,
      deviceId: deviceId,
      method: s.method,
      customerId: s.customerId,
      customerName: s.customerName,
      total: s.total,
      voidedAt: s.voidedAt,
      syncedAt: s.syncedAt,
      createdAt: s.createdAt,
      updatedAt: s.updatedAt,
      deletedAt: s.deletedAt,
    );

SaleLineRow saleLineRow(SaleLine l) => SaleLineRow(
      id: l.id,
      tenantId: l.tenantId,
      saleId: l.saleId,
      productId: l.productId,
      variantId: l.variantId,
      batchId: l.batchId,
      serialId: l.serialId,
      name: l.name,
      qtyMilli: l.qtyMilli,
      price: l.price,
      costSnapshot: l.costSnapshot,
      lineTotal: l.total,
      createdAt: l.createdAt,
      updatedAt: l.updatedAt,
      deletedAt: l.deletedAt,
    );

SaleLine saleLineFromRow(SaleLineRow r) => SaleLine(
      id: r.id,
      tenantId: r.tenantId,
      saleId: r.saleId,
      productId: r.productId,
      variantId: r.variantId,
      batchId: r.batchId,
      serialId: r.serialId,
      name: r.name,
      qtyMilli: r.qtyMilli,
      price: r.price,
      costSnapshot: r.costSnapshot,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      deletedAt: r.deletedAt,
    );

PaymentRow paymentRow(Payment p) => PaymentRow(
      id: p.id,
      tenantId: p.tenantId,
      saleId: p.saleId,
      method: p.method,
      amount: p.amount,
      received: p.received,
      createdAt: p.createdAt,
      updatedAt: p.updatedAt,
      deletedAt: p.deletedAt,
    );

Payment paymentFromRow(PaymentRow r) => Payment(
      id: r.id,
      tenantId: r.tenantId,
      saleId: r.saleId,
      method: r.method,
      amount: r.amount,
      received: r.received,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      deletedAt: r.deletedAt,
    );

/// Live lines / payments only (soft-deleted children are hidden).
Sale saleFromRow(SaleRow r, List<SaleLineRow> lines, List<PaymentRow> payments) => Sale(
      id: r.id,
      tenantId: r.tenantId,
      no: r.no,
      method: r.method,
      lines: [for (final l in lines) if (l.deletedAt == null) saleLineFromRow(l)],
      payments: [for (final p in payments) if (p.deletedAt == null) paymentFromRow(p)],
      customerId: r.customerId,
      customerName: r.customerName,
      voidedAt: r.voidedAt,
      syncedAt: r.syncedAt,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      deletedAt: r.deletedAt,
    );
