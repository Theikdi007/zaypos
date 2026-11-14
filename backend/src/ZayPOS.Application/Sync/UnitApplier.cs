using Microsoft.EntityFrameworkCore;
using ZayPOS.Application.Abstractions;
using ZayPOS.Domain.Catalog;
using ZayPOS.Domain.Common;
using ZayPOS.Domain.Customers;
using ZayPOS.Domain.Inventory;
using ZayPOS.Domain.Sales;
using ZayPOS.Domain.Sync;
using ZayPOS.Domain.Tenancy;
using static ZayPOS.Application.Sync.LastWriterWins;

namespace ZayPOS.Application.Sync;

/// <summary>
/// Applies the rows of ONE unit inside the caller's transaction (README §3.1 steps 2–4):
/// table rules from §3.3, server-side totals, and the §3.4 business checks as SyncIssues.
/// Throws <see cref="SyncRejectException"/> for shape/reference errors (nothing is kept).
/// </summary>
internal sealed class UnitApplier(IAppDb db, SyncCaller caller, PushUnit unit, UnitRows rows, DateTime now)
{
    private readonly DateTime _limit = now + SyncLimits.MaxClockAhead;
    private readonly HashSet<SyncIssueKind> _issueKinds = [];
    private readonly HashSet<Guid> _barcodeChanged = [];
    private readonly HashSet<Guid> _flaggedSerials = [];
    private readonly HashSet<Guid> _stockTouched = [];
    private readonly HashSet<Guid> _creditCustomers = [];
    private TimeSpan _maxAhead = TimeSpan.Zero;
    private CancellationToken _ct;

    public IReadOnlyList<SyncIssueKind> IssueKinds => [.. _issueKinds];

    // ================================================================ entry points

    /// <summary>
    /// voidSale is a state transition: if every sale in it is already in the target
    /// voided state on the server, the whole unit is skipped (its reversal movements
    /// and debt entries must not count twice).
    /// </summary>
    public async Task<bool> IsNoOpVoidAsync(CancellationToken ct)
    {
        _ct = ct;
        if (rows.Sales is not { Count: > 0 }) throw Reject("voidSale needs its sales row.");
        var transitions = 0;
        foreach (var r in rows.Sales)
        {
            var sale = await FindAsync<Sale>(RequireId(r.Id, "sales")) ?? throw Reject($"voidSale for unknown sale {r.Id}.");
            if ((sale.VoidedAt is not null) != (r.VoidedAt is not null)) transitions++;
        }
        return transitions == 0;
    }

    public async Task ApplyAsync(CancellationToken ct)
    {
        _ct = ct;
        NoteClock(unit.ClientTime);

        await ApplyTenantsAsync();
        await ApplyFeaturesAsync();
        await ApplyDevicesAsync();
        await UpsertAsync<ProductRow, Product>("products", rows.Products, CopyProduct);
        await UpsertAsync<ProductVariantRow, ProductVariant>("productVariants", rows.ProductVariants, CopyVariant);
        await UpsertAsync<ProductBatchRow, ProductBatch>("productBatches", rows.ProductBatches, CopyBatch);
        await UpsertAsync<CustomerRow, Customer>("customers", rows.Customers, CopyCustomer);
        await ApplySerialsAsync();
        await ApplySalesAsync();
        await InsertOnlyAsync<PaymentRow, Payment>("payments", rows.Payments, NewPayment);
        await InsertOnlyAsync<StockMovementRow, StockMovement>("stockMovements", rows.StockMovements, NewMovement);
        await InsertOnlyAsync<DebtEntryRow, DebtEntry>("debtEntries", rows.DebtEntries, NewDebtEntry);
    }

    /// <summary>Saves the rows, then runs the checks that need the post-unit ledgers (§3.4).</summary>
    public async Task SaveAndCheckAsync(CancellationToken ct)
    {
        _ct = ct;
        var stockBefore = await StockSumsAsync(); // DB only: this unit's movements are not saved yet
        await db.SaveChangesAsync(ct);

        await CheckNegativeStockAsync(stockBefore);
        await CheckCreditLimitsAsync();
        await CheckBarcodesAsync();
        if (_maxAhead > SyncLimits.MaxClockAhead)
            Issue(SyncIssueKind.ClockSkew, "Devices", caller.DeviceId,
                $"Device clock is {_maxAhead.TotalMinutes:0} min ahead of the server; edit times were clamped to server time + {SyncLimits.MaxClockAhead.TotalMinutes:0} min.");

        await db.SaveChangesAsync(ct);
    }

    // ================================================================ LWW tables

    private async Task UpsertAsync<TRow, T>(string table, List<TRow>? list, Func<TRow, T, bool, Task> copy)
        where TRow : LwwRow where T : class, ISyncedRow, new()
    {
        foreach (var r in list ?? [])
        {
            var id = RequireId(r.Id, table);
            RequireTenant(r.TenantId, table);
            var updatedAt = ClampEdit(Require(r.UpdatedAt, $"{table}.updatedAt"));
            NoteClock(r.CreatedAt);

            var existing = await FindAsync<T>(id);
            switch (Decide(existing?.UpdatedAt, existing?.DeletedAt, updatedAt, r.DeletedAt, r.Restore == true))
            {
                case LwwAction.Insert:
                    var entity = new T
                    {
                        Id = id, TenantId = caller.TenantId,
                        CreatedAt = Require(r.CreatedAt, $"{table}.createdAt"), UpdatedAt = updatedAt, DeletedAt = r.DeletedAt,
                    };
                    await copy(r, entity, true);
                    db.Set<T>().Add(entity);
                    break;
                case LwwAction.Update:
                    await copy(r, existing!, false);
                    existing!.UpdatedAt = updatedAt;
                    existing.DeletedAt = r.DeletedAt;
                    break;
                case LwwAction.DeleteOnly:
                    existing!.DeletedAt = r.DeletedAt;
                    break;
            }
        }
    }

    private Task CopyProduct(ProductRow r, Product p, bool isNew)
    {
        p.Name = SyncLimits.ProductName.Apply(r.Name)!;
        p.Category = SyncLimits.ProductCategory.Apply(r.Category)!;
        p.Unit = SyncLimits.ProductUnit.Apply(r.Unit)!;
        var barcode = SyncLimits.ProductBarcode.Apply(r.Barcode);
        if (barcode != p.Barcode || isNew) _barcodeChanged.Add(p.Id);
        p.Barcode = barcode;
        p.Cost = SyncLimits.ProductCost.Apply(Require(r.Cost, "products.cost"));
        p.Price = SyncLimits.ProductPrice.Apply(Require(r.Price, "products.price"));
        p.WholesalePrice = r.WholesalePrice is { } w ? SyncLimits.ProductWholesalePrice.Apply(w) : null;
        p.LowAlertMilli = Require(r.LowAlertMilli, "products.lowAlertMilli");
        p.WarrantyMonths = r.WarrantyMonths;
        p.ExpiryAlertDays = r.ExpiryAlertDays;
        p.Tint = Require(r.Tint, "products.tint");
        p.Initial = SyncLimits.ProductInitial.Apply(r.Initial)!;
        return Task.CompletedTask;
    }

    private async Task CopyVariant(ProductVariantRow r, ProductVariant v, bool isNew)
    {
        if (isNew) v.ProductId = await RequireRefAsync<Product>(r.ProductId, "productVariants.productId");
        v.Size = SyncLimits.VariantSize.Apply(r.Size)!;
        v.Color = SyncLimits.VariantColor.Apply(r.Color)!;
    }

    private async Task CopyBatch(ProductBatchRow r, ProductBatch b, bool isNew)
    {
        if (isNew) b.ProductId = await RequireRefAsync<Product>(r.ProductId, "productBatches.productId");
        b.BatchNo = SyncLimits.BatchNo.Apply(r.BatchNo)!;
        b.ExpiryDate = r.ExpiryDate;
    }

    private Task CopyCustomer(CustomerRow r, Customer c, bool isNew)
    {
        c.Name = SyncLimits.CustomerName.Apply(r.Name)!;
        // varchar(20): Myanmar digits become 0-9; anything else non-ASCII is dropped rather than rejecting the customer.
        c.Phone = SyncLimits.CustomerPhone.Apply(r.Phone) ?? "";
        c.Address = SyncLimits.CustomerAddress.Apply(r.Address);
        c.CreditLimit = r.CreditLimit is { } l ? SyncLimits.CustomerCreditLimit.Apply(l) : null;
        c.Note = SyncLimits.CustomerNote.Apply(r.Note);
        return Task.CompletedTask;
    }

    /// <summary>Only the shop's own name/township are client-editable (plan and phone are not).</summary>
    private async Task ApplyTenantsAsync()
    {
        foreach (var r in rows.Tenants ?? [])
        {
            if (r.Id != caller.TenantId || (r.TenantId is { } t && t != caller.TenantId))
                throw Reject("tenants row must be the caller's own tenant.");
            var tenant = await db.Set<Tenant>().FirstOrDefaultAsync(x => x.Id == caller.TenantId, _ct)
                         ?? throw Reject("tenant not found.");
            var updatedAt = ClampEdit(Require(r.UpdatedAt, "tenants.updatedAt"));
            if (updatedAt <= tenant.UpdatedAt) continue;
            tenant.Name = SyncLimits.TenantName.Apply(r.Name)!;
            tenant.Township = SyncLimits.TenantTownship.Apply(r.Township);
            tenant.UpdatedAt = updatedAt;
        }
    }

    private async Task ApplyFeaturesAsync()
    {
        foreach (var r in rows.TenantFeatures ?? [])
        {
            RequireTenant(r.TenantId, "tenantFeatures");
            var key = SyncLimits.FeatureKey.Apply(r.FeatureKey)!;
            var enabled = Require(r.Enabled, "tenantFeatures.enabled");
            var updatedAt = ClampEdit(Require(r.UpdatedAt, "tenantFeatures.updatedAt"));

            var existing = db.Set<TenantFeature>().Local.FirstOrDefault(f => f.FeatureKey == key)
                           ?? await db.Set<TenantFeature>().FirstOrDefaultAsync(f => f.FeatureKey == key, _ct);
            if (existing is null)
                db.Set<TenantFeature>().Add(new TenantFeature { TenantId = caller.TenantId, FeatureKey = key, Enabled = enabled, UpdatedAt = updatedAt });
            else if (updatedAt > existing.UpdatedAt)
            {
                existing.Enabled = enabled;
                existing.UpdatedAt = updatedAt;
            }
        }
    }

    /// <summary>Devices.LastSeq only ever moves forward: MAX(server, incoming), atomically.</summary>
    private async Task ApplyDevicesAsync()
    {
        foreach (var r in rows.Devices ?? [])
        {
            RequireTenant(r.TenantId, "devices");
            if (r.Id != caller.DeviceId) throw Reject("a device may only push its own devices row.");
            var seq = (int)SyncLimits.DeviceLastSeq.Apply(Require(r.LastSeq, "devices.lastSeq"));
            await db.Set<Device>()
                .Where(d => d.Id == caller.DeviceId && d.LastSeq < seq)
                .ExecuteUpdateAsync(s => s.SetProperty(d => d.LastSeq, seq).SetProperty(d => d.UpdatedAt, now), _ct);
        }
    }

    // ================================================================ serials

    /// <summary>
    /// Accept status changes; a "sold" claim on a serial already sold to ANOTHER sale line keeps
    /// the first sale's link, stores both sales and raises serialDoubleSold.
    /// </summary>
    private async Task ApplySerialsAsync()
    {
        foreach (var r in rows.ProductSerials ?? [])
        {
            var id = RequireId(r.Id, "productSerials");
            RequireTenant(r.TenantId, "productSerials");
            var updatedAt = ClampEdit(Require(r.UpdatedAt, "productSerials.updatedAt"));
            var status = Require(r.Status, "productSerials.status");

            var existing = await FindAsync<ProductSerial>(id);
            if (existing is null)
            {
                db.Set<ProductSerial>().Add(new ProductSerial
                {
                    Id = id, TenantId = caller.TenantId,
                    ProductId = await RequireRefAsync<Product>(r.ProductId, "productSerials.productId"),
                    Serial = SyncLimits.Serial.Apply(r.Serial)!,
                    Status = status, SaleLineId = r.SaleLineId,
                    CreatedAt = Require(r.CreatedAt, "productSerials.createdAt"), UpdatedAt = updatedAt, DeletedAt = r.DeletedAt,
                });
                continue;
            }

            if (status == SerialStatus.Sold && existing.Status == SerialStatus.Sold
                && existing.SaleLineId is { } first && r.SaleLineId != first)
            {
                FlagDoubleSold(existing, first, r.SaleLineId);
                continue;
            }

            // A sale is a real-world event: "sold" applies even if the row looks older.
            var take = status == SerialStatus.Sold && existing.Status != SerialStatus.Sold
                       || Decide(existing.UpdatedAt, existing.DeletedAt, updatedAt, r.DeletedAt, restore: false) == LwwAction.Update;
            if (take)
            {
                existing.Status = status;
                existing.SaleLineId = r.SaleLineId;
                if (r.Serial is not null) existing.Serial = SyncLimits.Serial.Apply(r.Serial)!;
                existing.DeletedAt ??= r.DeletedAt;
                existing.UpdatedAt = updatedAt > existing.UpdatedAt ? updatedAt : existing.UpdatedAt;
            }
            else if (r.DeletedAt is not null && existing.DeletedAt is null)
            {
                existing.DeletedAt = r.DeletedAt;
            }
        }
    }

    private void FlagDoubleSold(ProductSerial serial, Guid firstLine, Guid? secondLine)
    {
        if (!_flaggedSerials.Add(serial.Id)) return;
        Issue(SyncIssueKind.SerialDoubleSold, "ProductSerials", serial.Id,
            $"Serial {serial.Serial} sold twice: sale line {firstLine} and {secondLine?.ToString() ?? "(unknown)"}. Both sales were kept.");
    }

    // ================================================================ sales (insert-only + void transition)

    private async Task ApplySalesAsync()
    {
        var handledLines = new HashSet<Guid>();
        foreach (var r in rows.Sales ?? [])
        {
            var id = RequireId(r.Id, "sales");
            RequireTenant(r.TenantId, "sales");
            var existing = await FindAsync<Sale>(id);

            if (existing is not null)
            {
                // Insert-only, except the voided state of a voidSale unit (checked in IsNoOpVoidAsync).
                if (unit.Kind == UnitKinds.VoidSale && (existing.VoidedAt is not null) != (r.VoidedAt is not null))
                {
                    existing.VoidedAt = r.VoidedAt;
                    existing.UpdatedAt = ClampEdit(Require(r.UpdatedAt, "sales.updatedAt"));
                }
                continue;
            }

            var sale = new Sale
            {
                Id = id, TenantId = caller.TenantId,
                No = SyncLimits.SaleNo.Apply(r.No)!,
                DeviceId = await RequireRefAsync<Device>(r.DeviceId ?? caller.DeviceId, "sales.deviceId"),
                Method = Require(r.Method, "sales.method"),
                CustomerId = await OptionalRefAsync<Customer>(r.CustomerId, "sales.customerId"),
                CustomerName = SyncLimits.SaleCustomerName.Apply(r.CustomerName),
                VoidedAt = r.VoidedAt,
                CreatedAt = Require(r.CreatedAt, "sales.createdAt"),
                UpdatedAt = Require(r.UpdatedAt, "sales.updatedAt"),
                DeletedAt = r.DeletedAt,
                ReceivedAt = now,
            };
            NoteClock(sale.CreatedAt);
            if (sale.Method == PaymentMethod.Debt && sale.CustomerId is null)
                throw Reject("sales.customerId is required for a debt sale.");

            // Server computes every total from price × qty.
            var mismatches = new List<string>();
            long total = 0;
            foreach (var lr in (rows.SaleLines ?? []).Where(l => l.SaleId == id))
            {
                var line = await NewLineAsync(lr, sale.Id);
                if (line is null) continue;
                handledLines.Add(line.Id);
                total += line.LineTotal;
                if (lr.LineTotal is { } clientLine && clientLine != line.LineTotal)
                    mismatches.Add($"line {line.Id}: client {clientLine}, server {line.LineTotal}");
            }
            sale.Total = total;
            if (r.Total is { } clientTotal && clientTotal != total)
                mismatches.Insert(0, $"total: client {clientTotal}, server {total}");
            if (mismatches.Count > 0)
                Issue(SyncIssueKind.TotalMismatch, "Sales", sale.Id, $"Sale {sale.No}: " + string.Join("; ", mismatches));

            sale.No = await UniqueReceiptNoAsync(sale);
            db.Set<Sale>().Add(sale);
        }

        // Lines for a sale that is already on the server (not normally sent, but insert-only applies).
        foreach (var lr in rows.SaleLines ?? [])
        {
            if (handledLines.Contains(lr.Id)) continue;
            var saleId = await RequireRefAsync<Sale>(lr.SaleId, "saleLines.saleId");
            await NewLineAsync(lr, saleId);
        }
    }

    /// <summary>New line (or null if it already exists). Checks the serial it sells.</summary>
    private async Task<SaleLine?> NewLineAsync(SaleLineRow r, Guid saleId)
    {
        var id = RequireId(r.Id, "saleLines");
        RequireTenant(r.TenantId, "saleLines");
        if (await FindAsync<SaleLine>(id) is not null) return null;

        var qty = SyncLimits.SaleLineQty.Apply(Require(r.QtyMilli, "saleLines.qtyMilli"));
        var price = SyncLimits.SaleLinePrice.Apply(Require(r.Price, "saleLines.price"));
        var cost = SyncLimits.SaleLineCost.Apply(Require(r.CostSnapshot, "saleLines.costSnapshot"));

        var line = new SaleLine
        {
            Id = id, TenantId = caller.TenantId, SaleId = saleId,
            ProductId = await OptionalRefAsync<Product>(r.ProductId, "saleLines.productId"),
            VariantId = await OptionalRefAsync<ProductVariant>(r.VariantId, "saleLines.variantId"),
            BatchId = await OptionalRefAsync<ProductBatch>(r.BatchId, "saleLines.batchId"),
            SerialId = await OptionalRefAsync<ProductSerial>(r.SerialId, "saleLines.serialId"),
            Name = SyncLimits.SaleLineName.Apply(r.Name)!,
            QtyMilli = qty, Price = price, CostSnapshot = cost,
            LineTotal = Ledger.LineTotal(price, qty),
            CreatedAt = Require(r.CreatedAt, "saleLines.createdAt"),
            UpdatedAt = Require(r.UpdatedAt, "saleLines.updatedAt"),
            DeletedAt = r.DeletedAt,
        };

        // Serial sold by another line already on the server, without a serial row in this unit.
        if (line.SerialId is { } serialId && !(rows.ProductSerials ?? []).Any(s => s.Id == serialId))
        {
            var serial = await FindAsync<ProductSerial>(serialId);
            if (serial is { Status: SerialStatus.Sold, SaleLineId: { } first } && first != line.Id)
                FlagDoubleSold(serial, first, line.Id);
        }

        db.Set<SaleLine>().Add(line);
        return line;
    }

    /// <summary>
    /// UX_Sales_No can only collide when a reinstall reused a device code. The sale is real,
    /// so keep it under "A-1033*2" and tell the owner.
    /// </summary>
    private async Task<string> UniqueReceiptNoAsync(Sale sale)
    {
        if (!await NoTakenAsync(sale.No, sale.Id)) return sale.No;
        for (var n = 2; n < 100; n++)
        {
            var suffix = "*" + n;
            var candidate = (sale.No.Length + suffix.Length <= 12 ? sale.No : sale.No[..(12 - suffix.Length)]) + suffix;
            if (await NoTakenAsync(candidate, sale.Id)) continue;
            Issue(SyncIssueKind.DuplicateReceiptNo, "Sales", sale.Id,
                $"Receipt {sale.No} already exists (reinstalled app reusing a device code?). Stored as {candidate}.");
            return candidate;
        }
        throw Reject($"receipt number {sale.No} collides too often.");
    }

    private async Task<bool> NoTakenAsync(string no, Guid saleId) =>
        db.Set<Sale>().Local.Any(s => s.No == no && s.Id != saleId)
        || await db.Set<Sale>().AnyAsync(s => s.No == no && s.Id != saleId, _ct);

    // ================================================================ other insert-only ledgers

    private async Task InsertOnlyAsync<TRow, T>(string table, List<TRow>? list, Func<TRow, Task<T>> create)
        where TRow : SyncRow where T : class, ISyncedRow
    {
        foreach (var r in list ?? [])
        {
            RequireId(r.Id, table);
            RequireTenant(r.TenantId, table);
            if (await FindAsync<T>(r.Id) is not null) continue; // already applied
            NoteClock(r.CreatedAt);
            db.Set<T>().Add(await create(r));
        }
    }

    private async Task<Payment> NewPayment(PaymentRow r)
    {
        var method = Require(r.Method, "payments.method");
        if (method == PaymentMethod.Debt) throw Reject("payments.method can't be debt (debt is a sale method).");
        var amount = SyncLimits.PaymentAmount.Apply(Require(r.Amount, "payments.amount"));
        if (r.Received is { } rec && rec < amount) throw Reject("payments.received must be >= payments.amount.");
        return new Payment
        {
            Id = r.Id, TenantId = caller.TenantId,
            SaleId = await RequireRefAsync<Sale>(r.SaleId, "payments.saleId"),
            Method = method, Amount = amount, Received = r.Received,
            CreatedAt = Require(r.CreatedAt, "payments.createdAt"), UpdatedAt = Require(r.UpdatedAt, "payments.updatedAt"),
            DeletedAt = r.DeletedAt,
        };
    }

    private async Task<StockMovement> NewMovement(StockMovementRow r)
    {
        var m = new StockMovement
        {
            Id = r.Id, TenantId = caller.TenantId,
            ProductId = await RequireRefAsync<Product>(r.ProductId, "stockMovements.productId"),
            VariantId = await OptionalRefAsync<ProductVariant>(r.VariantId, "stockMovements.variantId"),
            BatchId = await OptionalRefAsync<ProductBatch>(r.BatchId, "stockMovements.batchId"),
            Type = Require(r.Type, "stockMovements.type"),
            QtyMilli = Require(r.QtyMilli, "stockMovements.qtyMilli"),
            SaleId = await OptionalRefAsync<Sale>(r.SaleId, "stockMovements.saleId"),
            Note = SyncLimits.StockMovementNote.Apply(r.Note) ?? "",
            DeviceId = await RequireRefAsync<Device>(r.DeviceId ?? caller.DeviceId, "stockMovements.deviceId"),
            CreatedAt = Require(r.CreatedAt, "stockMovements.createdAt"), UpdatedAt = Require(r.UpdatedAt, "stockMovements.updatedAt"),
            DeletedAt = r.DeletedAt,
        };
        if (m.DeletedAt is null) _stockTouched.Add(m.ProductId);
        return m;
    }

    private async Task<DebtEntry> NewDebtEntry(DebtEntryRow r)
    {
        var type = Require(r.Type, "debtEntries.type");
        var amount = Require(r.Amount, "debtEntries.amount");
        if (type != DebtEntryType.Adjustment) SyncLimits.DebtEntryAmount.Apply(amount); // only adjustments are signed
        if (r.Method == PaymentMethod.Debt) throw Reject("debtEntries.method can't be debt.");
        var e = new DebtEntry
        {
            Id = r.Id, TenantId = caller.TenantId,
            CustomerId = await RequireRefAsync<Customer>(r.CustomerId, "debtEntries.customerId"),
            Type = type, Amount = amount,
            SaleId = await OptionalRefAsync<Sale>(r.SaleId, "debtEntries.saleId"),
            SaleNo = SyncLimits.DebtEntrySaleNo.Apply(r.SaleNo),
            Method = r.Method,
            Note = SyncLimits.DebtEntryNote.Apply(r.Note),
            DeviceId = await RequireRefAsync<Device>(r.DeviceId ?? caller.DeviceId, "debtEntries.deviceId"),
            CreatedAt = Require(r.CreatedAt, "debtEntries.createdAt"), UpdatedAt = Require(r.UpdatedAt, "debtEntries.updatedAt"),
            DeletedAt = r.DeletedAt,
        };
        if (e.DeletedAt is null && e.Effect > 0) _creditCustomers.Add(e.CustomerId);
        return e;
    }

    // ================================================================ business checks (§3.4)

    private async Task<Dictionary<Guid, long>> StockSumsAsync()
    {
        if (_stockTouched.Count == 0) return [];
        var ids = _stockTouched.ToList();
        return await db.Set<StockMovement>()
            .Where(m => ids.Contains(m.ProductId) && m.DeletedAt == null)
            .GroupBy(m => m.ProductId)
            .Select(g => new { g.Key, Sum = g.Sum(m => m.QtyMilli) })
            .ToDictionaryAsync(x => x.Key, x => x.Sum, _ct);
    }

    /// <summary>
    /// Flag when a product's ledger goes from >= 0 to below 0 in this unit (stock feature on).
    /// Products whose stock is not tracked yet — no live restock/adjustment with qty > 0 ever,
    /// e.g. imported presets — are skipped: their ledger sum means nothing yet.
    /// Mobile twin: <c>startsTracking</c> in stock_movement.dart.
    /// </summary>
    private async Task CheckNegativeStockAsync(Dictionary<Guid, long> before)
    {
        if (_stockTouched.Count == 0) return;
        var stockOn = await db.Set<TenantFeature>()
            .Where(f => f.FeatureKey == FeatureKeys.Stock).Select(f => f.Enabled).FirstOrDefaultAsync(_ct);
        if (!stockOn) return;

        var ids = _stockTouched.ToList();
        var tracked = (await db.Set<StockMovement>()
            .Where(m => ids.Contains(m.ProductId) && m.DeletedAt == null && m.QtyMilli > 0
                && (m.Type == StockMovementType.Restock || m.Type == StockMovementType.Adjustment))
            .Select(m => m.ProductId).Distinct().ToListAsync(_ct)).ToHashSet();

        foreach (var (productId, after) in await StockSumsAsync())
        {
            if (!tracked.Contains(productId)) continue;
            if (after >= 0 || before.GetValueOrDefault(productId) < 0) continue;
            var name = await db.Set<Product>().Where(p => p.Id == productId).Select(p => p.Name).FirstOrDefaultAsync(_ct);
            Issue(SyncIssueKind.NegativeStock, "Products", productId,
                $"{name}: stock is {Ledger.FormatQty(after)} after this sync. The sale was kept.");
        }
    }

    private async Task CheckCreditLimitsAsync()
    {
        foreach (var customerId in _creditCustomers)
        {
            var customer = await FindAsync<Customer>(customerId);
            if (customer?.CreditLimit is not { } limit) continue;
            var balance = await db.Set<DebtEntry>()
                .Where(e => e.CustomerId == customerId && e.DeletedAt == null)
                .SumAsync(e => e.Type == DebtEntryType.Payment ? -e.Amount : e.Amount, _ct);
            if (balance > limit)
                Issue(SyncIssueKind.CreditLimitExceeded, "Customers", customerId,
                    $"{customer.Name} owes {balance:N0} Ks, over the {limit:N0} Ks limit.");
        }
    }

    private async Task CheckBarcodesAsync()
    {
        foreach (var productId in _barcodeChanged)
        {
            var p = await FindAsync<Product>(productId);
            if (p is not { Barcode: { } barcode, DeletedAt: null }) continue;
            var others = await db.Set<Product>()
                .Where(o => o.Id != productId && o.Barcode == barcode && o.DeletedAt == null)
                .Select(o => o.Name).ToListAsync(_ct);
            if (others.Count > 0)
                Issue(SyncIssueKind.DuplicateBarcode, "Products", productId,
                    $"Barcode {barcode} is also used by: {string.Join(", ", others)}.");
        }
    }

    private void Issue(SyncIssueKind kind, string table, Guid entityId, string detail)
    {
        _issueKinds.Add(kind);
        db.Set<SyncIssue>().Add(new SyncIssue
        {
            Id = Guid.CreateVersion7(), TenantId = caller.TenantId, Kind = kind,
            EntityTable = table, EntityId = entityId,
            Detail = detail.Length <= SyncLimits.IssueDetailMaxLength ? detail : detail[..SyncLimits.IssueDetailMaxLength],
            DeviceId = caller.DeviceId, CreatedAt = now, UpdatedAt = now,
        });
    }

    // ================================================================ helpers

    /// <summary>Tracked first (rows added earlier in this unit), then the tenant-filtered database.</summary>
    private async Task<T?> FindAsync<T>(Guid id) where T : class, ISyncedRow =>
        db.Set<T>().Local.FirstOrDefault(e => e.Id == id)
        ?? await db.Set<T>().FirstOrDefaultAsync(e => e.Id == id, _ct);

    private async Task<Guid> RequireRefAsync<T>(Guid? id, string field) where T : class, ISyncedRow
    {
        var value = Require(id, field);
        if (value == Guid.Empty || await FindAsync<T>(value) is null)
            throw Reject($"{field} {value} does not exist in this shop.");
        return value;
    }

    private async Task<Guid?> OptionalRefAsync<T>(Guid? id, string field) where T : class, ISyncedRow =>
        id is null ? null : await RequireRefAsync<T>(id, field);

    private Guid RequireId(Guid id, string table) =>
        id == Guid.Empty ? throw Reject($"{table} row without a valid id.") : id;

    private void RequireTenant(Guid? tenantId, string table)
    {
        if (tenantId is { } t && t != caller.TenantId)
            throw Reject($"{table} row belongs to another tenant.");
    }

    /// <summary>LWW edit time: clamped to server time + 5 min (clockSkew issue).</summary>
    private DateTime ClampEdit(DateTime t)
    {
        NoteClock(t);
        return t > _limit ? _limit : t;
    }

    private void NoteClock(DateTime? t)
    {
        if (t is { } v && v - now > _maxAhead) _maxAhead = v - now;
    }

    private static T Require<T>(T? value, string field) where T : struct =>
        value ?? throw Reject($"{field} is required.");

    private static SyncRejectException Reject(string reason) => new(reason);
}
