using ZayPOS.Domain.Catalog;
using ZayPOS.Domain.Customers;
using ZayPOS.Domain.Inventory;
using ZayPOS.Domain.Sales;
using ZayPOS.Domain.Sync;
using ZayPOS.Domain.Tenancy;

namespace ZayPOS.Application.Sync;

/// <summary>Entity → wire row for pull. Soft-deleted rows are included (DeletedAt set).</summary>
public static class RowMapping
{
    public static TenantRow ToRow(this Tenant t) => new()
    {
        Id = t.Id, TenantId = t.Id, Name = t.Name, TemplateId = t.TemplateId, Township = t.Township,
        Plan = t.Plan, PlanExpiresAt = t.PlanExpiresAt, CreatedAt = t.CreatedAt, UpdatedAt = t.UpdatedAt, DeletedAt = t.DeletedAt,
    };

    public static TenantFeatureRow ToRow(this TenantFeature f) => new()
    {
        TenantId = f.TenantId, FeatureKey = f.FeatureKey, Enabled = f.Enabled, UpdatedAt = f.UpdatedAt,
    };

    public static DeviceRow ToRow(this Device d) => new()
    {
        Id = d.Id, TenantId = d.TenantId, Code = d.Code, Name = d.Name, LastSeq = d.LastSeq, LastSyncAt = d.LastSyncAt,
        CreatedAt = d.CreatedAt, UpdatedAt = d.UpdatedAt, DeletedAt = d.DeletedAt,
    };

    public static ProductRow ToRow(this Product p) => new()
    {
        Id = p.Id, TenantId = p.TenantId, Name = p.Name, Category = p.Category, Unit = p.Unit, Barcode = p.Barcode,
        Cost = p.Cost, Price = p.Price, WholesalePrice = p.WholesalePrice, LowAlertMilli = p.LowAlertMilli,
        WarrantyMonths = p.WarrantyMonths, ExpiryAlertDays = p.ExpiryAlertDays, Tint = p.Tint, Initial = p.Initial,
        CreatedAt = p.CreatedAt, UpdatedAt = p.UpdatedAt, DeletedAt = p.DeletedAt,
    };

    public static ProductVariantRow ToRow(this ProductVariant v) => new()
    {
        Id = v.Id, TenantId = v.TenantId, ProductId = v.ProductId, Size = v.Size, Color = v.Color,
        CreatedAt = v.CreatedAt, UpdatedAt = v.UpdatedAt, DeletedAt = v.DeletedAt,
    };

    public static ProductBatchRow ToRow(this ProductBatch b) => new()
    {
        Id = b.Id, TenantId = b.TenantId, ProductId = b.ProductId, BatchNo = b.BatchNo, ExpiryDate = b.ExpiryDate,
        CreatedAt = b.CreatedAt, UpdatedAt = b.UpdatedAt, DeletedAt = b.DeletedAt,
    };

    public static ProductSerialRow ToRow(this ProductSerial s) => new()
    {
        Id = s.Id, TenantId = s.TenantId, ProductId = s.ProductId, Serial = s.Serial, Status = s.Status, SaleLineId = s.SaleLineId,
        CreatedAt = s.CreatedAt, UpdatedAt = s.UpdatedAt, DeletedAt = s.DeletedAt,
    };

    public static CustomerRow ToRow(this Customer c) => new()
    {
        Id = c.Id, TenantId = c.TenantId, Name = c.Name, Phone = c.Phone, Address = c.Address,
        CreditLimit = c.CreditLimit, Note = c.Note, CreatedAt = c.CreatedAt, UpdatedAt = c.UpdatedAt, DeletedAt = c.DeletedAt,
    };

    public static SaleRow ToRow(this Sale s) => new()
    {
        Id = s.Id, TenantId = s.TenantId, No = s.No, DeviceId = s.DeviceId, Method = s.Method,
        CustomerId = s.CustomerId, CustomerName = s.CustomerName, Total = s.Total, VoidedAt = s.VoidedAt,
        CreatedAt = s.CreatedAt, UpdatedAt = s.UpdatedAt, DeletedAt = s.DeletedAt, SyncedAt = s.ReceivedAt,
    };

    public static SaleLineRow ToRow(this SaleLine l) => new()
    {
        Id = l.Id, TenantId = l.TenantId, SaleId = l.SaleId, ProductId = l.ProductId, VariantId = l.VariantId,
        BatchId = l.BatchId, SerialId = l.SerialId, Name = l.Name, QtyMilli = l.QtyMilli, Price = l.Price,
        CostSnapshot = l.CostSnapshot, LineTotal = l.LineTotal,
        CreatedAt = l.CreatedAt, UpdatedAt = l.UpdatedAt, DeletedAt = l.DeletedAt,
    };

    public static PaymentRow ToRow(this Payment p) => new()
    {
        Id = p.Id, TenantId = p.TenantId, SaleId = p.SaleId, Method = p.Method, Amount = p.Amount, Received = p.Received,
        CreatedAt = p.CreatedAt, UpdatedAt = p.UpdatedAt, DeletedAt = p.DeletedAt,
    };

    public static StockMovementRow ToRow(this StockMovement m) => new()
    {
        Id = m.Id, TenantId = m.TenantId, ProductId = m.ProductId, VariantId = m.VariantId, BatchId = m.BatchId,
        Type = m.Type, QtyMilli = m.QtyMilli, SaleId = m.SaleId, Note = m.Note, DeviceId = m.DeviceId,
        CreatedAt = m.CreatedAt, UpdatedAt = m.UpdatedAt, DeletedAt = m.DeletedAt,
    };

    public static DebtEntryRow ToRow(this DebtEntry e) => new()
    {
        Id = e.Id, TenantId = e.TenantId, CustomerId = e.CustomerId, Type = e.Type, Amount = e.Amount,
        SaleId = e.SaleId, SaleNo = e.SaleNo, Method = e.Method, Note = e.Note, DeviceId = e.DeviceId,
        CreatedAt = e.CreatedAt, UpdatedAt = e.UpdatedAt, DeletedAt = e.DeletedAt,
    };

    public static SyncIssueRow ToRow(this SyncIssue i) => new()
    {
        Id = i.Id, TenantId = i.TenantId, Kind = i.Kind, EntityTable = i.EntityTable, EntityId = i.EntityId,
        Detail = i.Detail, DeviceId = i.DeviceId, ResolvedAt = i.ResolvedAt,
        CreatedAt = i.CreatedAt, UpdatedAt = i.UpdatedAt, DeletedAt = i.DeletedAt,
    };
}
