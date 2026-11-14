/* =====================================================================
   ZayPOS — SQL Server schema (v1)
   Source of truth for EF Core entities. Mirrors the Flutter domain models
   in mobile/lib/features/**/domain.

   Conventions
   - Ids: uniqueidentifier, generated on the CLIENT (UUID v7). Server never
     generates ids for synced rows.
   - Money: bigint kyats (no decimals). Quantity: bigint milli-units
     (1 unit = 1000, 2.5 ft = 2500).
   - Time: datetime2(3), always UTC.
   - Text: nvarchar (Myanmar Unicode).
   - Every tenant table has TenantId, CreatedAt, UpdatedAt, DeletedAt
     (soft delete) and Version (rowversion) = the sync "pull" cursor.
   - Ledgers (StockMovements, DebtEntries) and sale data are append-only:
     rows are never updated except Sales.VoidedAt and soft-delete flags.
   - PK is NONCLUSTERED on Id; each tenant table is CLUSTERED on
     (TenantId, CreatedAt) so a shop's rows sit together on disk.
   ===================================================================== */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ---------------------------------------------------------------------
   1. Tenants, features, users, devices, auth
   --------------------------------------------------------------------- */

CREATE TABLE dbo.Tenants (
    Id              uniqueidentifier NOT NULL,
    Name            nvarchar(120)    NOT NULL,           -- ဆိုင်အမည်
    TemplateId      varchar(20)      NOT NULL,           -- grocery|pharmacy|phone|fashion|hardware|service|restaurant|other
    Township        nvarchar(80)     NULL,
    Phone           varchar(20)      NOT NULL,           -- owner phone, E.164 (+959...)
    [Plan]          varchar(20)      NOT NULL CONSTRAINT DF_Tenants_Plan DEFAULT ('free'),  -- free|pro
    PlanExpiresAt   datetime2(3)     NULL,
    CreatedAt       datetime2(3)     NOT NULL,
    UpdatedAt       datetime2(3)     NOT NULL,
    DeletedAt       datetime2(3)     NULL,
    Version         rowversion       NOT NULL,
    CONSTRAINT PK_Tenants PRIMARY KEY CLUSTERED (Id),
    CONSTRAINT CK_Tenants_Plan CHECK ([Plan] IN ('free','pro'))
);

/* Feature flags as key/value so a new flag needs no migration.
   Keys = Dart TenantFeatures fields: quickSale, stock, presetCatalog,
   expiryBatch, serialWarranty, variants, decimalQty, quotation, serviceItems. */
CREATE TABLE dbo.TenantFeatures (
    TenantId        uniqueidentifier NOT NULL,
    FeatureKey      varchar(40)      NOT NULL,
    Enabled         bit              NOT NULL,
    UpdatedAt       datetime2(3)     NOT NULL,
    Version         rowversion       NOT NULL,
    CONSTRAINT PK_TenantFeatures PRIMARY KEY CLUSTERED (TenantId, FeatureKey),
    CONSTRAINT FK_TenantFeatures_Tenant FOREIGN KEY (TenantId) REFERENCES dbo.Tenants (Id)
);

CREATE TABLE dbo.Users (
    Id              uniqueidentifier NOT NULL,
    TenantId        uniqueidentifier NOT NULL,
    Phone           varchar(20)      NOT NULL,
    Name            nvarchar(80)     NOT NULL,
    Role            varchar(10)      NOT NULL,           -- owner|staff (v1: owner only)
    PinHash         varchar(200)     NOT NULL,           -- ASP.NET Core PasswordHasher output
    FailedPinCount  int              NOT NULL CONSTRAINT DF_Users_Failed DEFAULT (0),
    LockedUntil     datetime2(3)     NULL,
    CreatedAt       datetime2(3)     NOT NULL,
    UpdatedAt       datetime2(3)     NOT NULL,
    DeletedAt       datetime2(3)     NULL,
    Version         rowversion       NOT NULL,
    CONSTRAINT PK_Users PRIMARY KEY NONCLUSTERED (Id),
    CONSTRAINT FK_Users_Tenant FOREIGN KEY (TenantId) REFERENCES dbo.Tenants (Id),
    CONSTRAINT CK_Users_Role CHECK (Role IN ('owner','staff'))
);
CREATE CLUSTERED INDEX CX_Users ON dbo.Users (TenantId, CreatedAt);
CREATE UNIQUE INDEX UX_Users_Phone ON dbo.Users (Phone) WHERE DeletedAt IS NULL;

/* One row per installed app. Code gives receipt numbers their prefix
   ("A-1033"); LastSeq is the highest number this device has issued
   (client-owned; server only ever moves it forward). */
CREATE TABLE dbo.Devices (
    Id              uniqueidentifier NOT NULL,
    TenantId        uniqueidentifier NOT NULL,
    Code            varchar(3)       NOT NULL,           -- A, B, ... Z, AA ...
    Name            nvarchar(60)     NULL,               -- "Samsung A15"
    LastSeq         int              NOT NULL CONSTRAINT DF_Devices_Seq DEFAULT (0),
    LastSyncAt      datetime2(3)     NULL,
    CreatedAt       datetime2(3)     NOT NULL,
    UpdatedAt       datetime2(3)     NOT NULL,
    DeletedAt       datetime2(3)     NULL,
    Version         rowversion       NOT NULL,
    CONSTRAINT PK_Devices PRIMARY KEY NONCLUSTERED (Id),
    CONSTRAINT FK_Devices_Tenant FOREIGN KEY (TenantId) REFERENCES dbo.Tenants (Id)
);
CREATE CLUSTERED INDEX CX_Devices ON dbo.Devices (TenantId, CreatedAt);
CREATE UNIQUE INDEX UX_Devices_Code ON dbo.Devices (TenantId, Code);

CREATE TABLE dbo.RefreshTokens (
    Id              uniqueidentifier NOT NULL,
    UserId          uniqueidentifier NOT NULL,
    DeviceId        uniqueidentifier NOT NULL,
    TokenHash       varbinary(32)    NOT NULL,           -- SHA-256 of the opaque token
    ExpiresAt       datetime2(3)     NOT NULL,
    RevokedAt       datetime2(3)     NULL,
    ReplacedById    uniqueidentifier NULL,               -- rotation chain
    CreatedAt       datetime2(3)     NOT NULL,
    CONSTRAINT PK_RefreshTokens PRIMARY KEY (Id),
    CONSTRAINT FK_RefreshTokens_User FOREIGN KEY (UserId) REFERENCES dbo.Users (Id),
    CONSTRAINT FK_RefreshTokens_Device FOREIGN KEY (DeviceId) REFERENCES dbo.Devices (Id)
);
CREATE UNIQUE INDEX UX_RefreshTokens_Hash ON dbo.RefreshTokens (TokenHash);

CREATE TABLE dbo.OtpChallenges (
    Id              uniqueidentifier NOT NULL,
    Phone           varchar(20)      NOT NULL,
    CodeHash        varbinary(32)    NOT NULL,
    Purpose         varchar(10)      NOT NULL,           -- register|reset
    Attempts        int              NOT NULL CONSTRAINT DF_Otp_Attempts DEFAULT (0),
    ExpiresAt       datetime2(3)     NOT NULL,
    ConsumedAt      datetime2(3)     NULL,
    CreatedAt       datetime2(3)     NOT NULL,
    CONSTRAINT PK_OtpChallenges PRIMARY KEY (Id)
);
CREATE INDEX IX_Otp_Phone ON dbo.OtpChallenges (Phone, CreatedAt DESC);
GO

/* ---------------------------------------------------------------------
   2. Catalog
   --------------------------------------------------------------------- */

CREATE TABLE dbo.Products (
    Id              uniqueidentifier NOT NULL,
    TenantId        uniqueidentifier NOT NULL,
    Name            nvarchar(150)    NOT NULL,
    Category        nvarchar(60)     NOT NULL,
    Unit            nvarchar(20)     NOT NULL,           -- ခု, ပြည်, ပေ ...
    Barcode         varchar(64)      NULL,
    Cost            bigint           NOT NULL,           -- kyats
    Price           bigint           NOT NULL,           -- kyats
    WholesalePrice  bigint           NULL,               -- kyats (quotation)
    LowAlertMilli   bigint           NOT NULL,
    WarrantyMonths  int              NULL,               -- serialWarranty
    ExpiryAlertDays int              NULL,               -- expiryBatch
    Tint            int              NOT NULL,           -- ARGB tile color (UI)
    Initial         nvarchar(4)      NOT NULL,           -- tile letter (UI)
    CreatedAt       datetime2(3)     NOT NULL,
    UpdatedAt       datetime2(3)     NOT NULL,
    DeletedAt       datetime2(3)     NULL,
    Version         rowversion       NOT NULL,
    CONSTRAINT PK_Products PRIMARY KEY NONCLUSTERED (Id),
    CONSTRAINT FK_Products_Tenant FOREIGN KEY (TenantId) REFERENCES dbo.Tenants (Id),
    CONSTRAINT CK_Products_Money CHECK (Cost >= 0 AND Price >= 0 AND (WholesalePrice IS NULL OR WholesalePrice >= 0))
);
CREATE CLUSTERED INDEX CX_Products ON dbo.Products (TenantId, CreatedAt);
/* Barcodes are NOT unique: two devices may add the same item offline.
   Duplicates are surfaced as a SyncIssue, never rejected. */
CREATE INDEX IX_Products_Barcode ON dbo.Products (TenantId, Barcode) WHERE Barcode IS NOT NULL AND DeletedAt IS NULL;

CREATE TABLE dbo.ProductVariants (
    Id              uniqueidentifier NOT NULL,
    TenantId        uniqueidentifier NOT NULL,
    ProductId       uniqueidentifier NOT NULL,
    Size            nvarchar(20)     NOT NULL,
    Color           nvarchar(30)     NOT NULL,
    CreatedAt       datetime2(3)     NOT NULL,
    UpdatedAt       datetime2(3)     NOT NULL,
    DeletedAt       datetime2(3)     NULL,
    Version         rowversion       NOT NULL,
    CONSTRAINT PK_ProductVariants PRIMARY KEY NONCLUSTERED (Id),
    CONSTRAINT FK_ProductVariants_Product FOREIGN KEY (ProductId) REFERENCES dbo.Products (Id)
);
CREATE CLUSTERED INDEX CX_ProductVariants ON dbo.ProductVariants (TenantId, CreatedAt);
CREATE INDEX IX_ProductVariants_Product ON dbo.ProductVariants (ProductId);

/* Batch stock is NOT stored here: it is the sum of StockMovements with
   this BatchId. (Dart ProductBatch.qtyMilli becomes a read-model value.) */
CREATE TABLE dbo.ProductBatches (
    Id              uniqueidentifier NOT NULL,
    TenantId        uniqueidentifier NOT NULL,
    ProductId       uniqueidentifier NOT NULL,
    BatchNo         nvarchar(40)     NOT NULL,
    ExpiryDate      date             NULL,
    CreatedAt       datetime2(3)     NOT NULL,
    UpdatedAt       datetime2(3)     NOT NULL,
    DeletedAt       datetime2(3)     NULL,
    Version         rowversion       NOT NULL,
    CONSTRAINT PK_ProductBatches PRIMARY KEY NONCLUSTERED (Id),
    CONSTRAINT FK_ProductBatches_Product FOREIGN KEY (ProductId) REFERENCES dbo.Products (Id)
);
CREATE CLUSTERED INDEX CX_ProductBatches ON dbo.ProductBatches (TenantId, CreatedAt);
CREATE INDEX IX_ProductBatches_Expiry ON dbo.ProductBatches (TenantId, ExpiryDate) WHERE DeletedAt IS NULL;

CREATE TABLE dbo.ProductSerials (
    Id              uniqueidentifier NOT NULL,
    TenantId        uniqueidentifier NOT NULL,
    ProductId       uniqueidentifier NOT NULL,
    Serial          varchar(40)      NOT NULL,           -- IMEI / serial
    Status          varchar(10)      NOT NULL,           -- inStock|sold
    SaleLineId      uniqueidentifier NULL,
    CreatedAt       datetime2(3)     NOT NULL,
    UpdatedAt       datetime2(3)     NOT NULL,
    DeletedAt       datetime2(3)     NULL,
    Version         rowversion       NOT NULL,
    CONSTRAINT PK_ProductSerials PRIMARY KEY NONCLUSTERED (Id),
    CONSTRAINT FK_ProductSerials_Product FOREIGN KEY (ProductId) REFERENCES dbo.Products (Id),
    CONSTRAINT CK_ProductSerials_Status CHECK (Status IN ('inStock','sold'))
);
CREATE CLUSTERED INDEX CX_ProductSerials ON dbo.ProductSerials (TenantId, CreatedAt);
CREATE INDEX IX_ProductSerials_Serial ON dbo.ProductSerials (TenantId, Serial) WHERE DeletedAt IS NULL;

/* Global (not per tenant) starter catalog per shop template. */
CREATE TABLE dbo.PresetProducts (
    Id              uniqueidentifier NOT NULL,
    TemplateId      varchar(20)      NOT NULL,
    Name            nvarchar(150)    NOT NULL,
    Category        nvarchar(60)     NOT NULL,
    Unit            nvarchar(20)     NOT NULL,
    Barcode         varchar(64)      NULL,
    SuggestedPrice  bigint           NULL,
    SortOrder       int              NOT NULL CONSTRAINT DF_Preset_Sort DEFAULT (0),
    UpdatedAt       datetime2(3)     NOT NULL,
    CONSTRAINT PK_PresetProducts PRIMARY KEY NONCLUSTERED (Id)
);
CREATE CLUSTERED INDEX CX_PresetProducts ON dbo.PresetProducts (TemplateId, SortOrder);
GO

/* ---------------------------------------------------------------------
   3. Stock ledger (append-only). Stock on hand = SUM(QtyMilli).
   --------------------------------------------------------------------- */

CREATE TABLE dbo.StockMovements (
    Id              uniqueidentifier NOT NULL,
    TenantId        uniqueidentifier NOT NULL,
    ProductId       uniqueidentifier NOT NULL,
    VariantId       uniqueidentifier NULL,
    BatchId         uniqueidentifier NULL,
    Type            varchar(12)      NOT NULL,           -- sale|restock|adjustment|voidReturn
    QtyMilli        bigint           NOT NULL,           -- signed: + in, - out
    SaleId          uniqueidentifier NULL,
    Note            nvarchar(200)    NOT NULL CONSTRAINT DF_Stock_Note DEFAULT (N''),
    DeviceId        uniqueidentifier NULL,
    CreatedAt       datetime2(3)     NOT NULL,
    UpdatedAt       datetime2(3)     NOT NULL,
    DeletedAt       datetime2(3)     NULL,
    Version         rowversion       NOT NULL,
    CONSTRAINT PK_StockMovements PRIMARY KEY NONCLUSTERED (Id),
    CONSTRAINT FK_StockMovements_Product FOREIGN KEY (ProductId) REFERENCES dbo.Products (Id),
    CONSTRAINT FK_StockMovements_Variant FOREIGN KEY (VariantId) REFERENCES dbo.ProductVariants (Id),
    CONSTRAINT FK_StockMovements_Batch FOREIGN KEY (BatchId) REFERENCES dbo.ProductBatches (Id),
    CONSTRAINT CK_StockMovements_Type CHECK (Type IN ('sale','restock','adjustment','voidReturn'))
);
CREATE CLUSTERED INDEX CX_StockMovements ON dbo.StockMovements (TenantId, CreatedAt);
CREATE INDEX IX_StockMovements_Product ON dbo.StockMovements (TenantId, ProductId) INCLUDE (QtyMilli, VariantId, BatchId, DeletedAt);
GO

/* ---------------------------------------------------------------------
   4. Customers and debt ledger (append-only). Balance = SUM(effect).
   --------------------------------------------------------------------- */

CREATE TABLE dbo.Customers (
    Id              uniqueidentifier NOT NULL,
    TenantId        uniqueidentifier NOT NULL,
    Name            nvarchar(100)    NOT NULL,
    Phone           varchar(20)      NOT NULL CONSTRAINT DF_Customers_Phone DEFAULT (''),
    Address         nvarchar(200)    NULL,
    CreditLimit     bigint           NULL,               -- kyats
    Note            nvarchar(300)    NULL,
    CreatedAt       datetime2(3)     NOT NULL,
    UpdatedAt       datetime2(3)     NOT NULL,
    DeletedAt       datetime2(3)     NULL,
    Version         rowversion       NOT NULL,
    CONSTRAINT PK_Customers PRIMARY KEY NONCLUSTERED (Id),
    CONSTRAINT FK_Customers_Tenant FOREIGN KEY (TenantId) REFERENCES dbo.Tenants (Id)
);
CREATE CLUSTERED INDEX CX_Customers ON dbo.Customers (TenantId, CreatedAt);

/* Amount sign rules (same as Dart DebtEntry.effect):
   creditSale: Amount > 0, effect +Amount
   payment:    Amount > 0, effect -Amount
   adjustment: Amount signed, effect +Amount (void reversal = -total) */
CREATE TABLE dbo.DebtEntries (
    Id              uniqueidentifier NOT NULL,
    TenantId        uniqueidentifier NOT NULL,
    CustomerId      uniqueidentifier NOT NULL,
    Type            varchar(12)      NOT NULL,           -- creditSale|payment|adjustment
    Amount          bigint           NOT NULL,
    SaleId          uniqueidentifier NULL,
    SaleNo          varchar(12)      NULL,               -- receipt no snapshot
    Method          varchar(10)      NULL,               -- payment: cash|kbz|wave
    Note            nvarchar(200)    NULL,
    DeviceId        uniqueidentifier NULL,
    CreatedAt       datetime2(3)     NOT NULL,
    UpdatedAt       datetime2(3)     NOT NULL,
    DeletedAt       datetime2(3)     NULL,
    Version         rowversion       NOT NULL,
    CONSTRAINT PK_DebtEntries PRIMARY KEY NONCLUSTERED (Id),
    CONSTRAINT FK_DebtEntries_Customer FOREIGN KEY (CustomerId) REFERENCES dbo.Customers (Id),
    CONSTRAINT CK_DebtEntries_Type CHECK (Type IN ('creditSale','payment','adjustment')),
    CONSTRAINT CK_DebtEntries_Sign CHECK (Type = 'adjustment' OR Amount > 0)
);
CREATE CLUSTERED INDEX CX_DebtEntries ON dbo.DebtEntries (TenantId, CreatedAt);
CREATE INDEX IX_DebtEntries_Customer ON dbo.DebtEntries (TenantId, CustomerId) INCLUDE (Type, Amount, DeletedAt, CreatedAt);
GO

/* ---------------------------------------------------------------------
   5. Sales
   --------------------------------------------------------------------- */

CREATE TABLE dbo.Sales (
    Id              uniqueidentifier NOT NULL,
    TenantId        uniqueidentifier NOT NULL,
    [No]            varchar(12)      NOT NULL,           -- "A-1033"
    DeviceId        uniqueidentifier NOT NULL,
    Method          varchar(10)      NOT NULL,           -- cash|kbz|wave|debt
    CustomerId      uniqueidentifier NULL,               -- required when Method = debt
    CustomerName    nvarchar(100)    NULL,               -- snapshot
    Total           bigint           NOT NULL,           -- kyats, recomputed by server from lines
    VoidedAt        datetime2(3)     NULL,
    CreatedAt       datetime2(3)     NOT NULL,           -- sale time on the device (UTC)
    UpdatedAt       datetime2(3)     NOT NULL,
    DeletedAt       datetime2(3)     NULL,
    ReceivedAt      datetime2(3)     NOT NULL CONSTRAINT DF_Sales_Received DEFAULT (SYSUTCDATETIME()),  -- server arrival (Dart Sale.syncedAt)
    Version         rowversion       NOT NULL,
    CONSTRAINT PK_Sales PRIMARY KEY NONCLUSTERED (Id),
    CONSTRAINT FK_Sales_Tenant FOREIGN KEY (TenantId) REFERENCES dbo.Tenants (Id),
    CONSTRAINT FK_Sales_Device FOREIGN KEY (DeviceId) REFERENCES dbo.Devices (Id),
    CONSTRAINT FK_Sales_Customer FOREIGN KEY (CustomerId) REFERENCES dbo.Customers (Id),
    CONSTRAINT CK_Sales_Method CHECK (Method IN ('cash','kbz','wave','debt')),
    CONSTRAINT CK_Sales_DebtCustomer CHECK (Method <> 'debt' OR CustomerId IS NOT NULL)
);
CREATE CLUSTERED INDEX CX_Sales ON dbo.Sales (TenantId, CreatedAt);
CREATE UNIQUE INDEX UX_Sales_No ON dbo.Sales (TenantId, [No]);

CREATE TABLE dbo.SaleLines (
    Id              uniqueidentifier NOT NULL,
    TenantId        uniqueidentifier NOT NULL,
    SaleId          uniqueidentifier NOT NULL,
    ProductId       uniqueidentifier NULL,               -- NULL = Quick Sale line
    VariantId       uniqueidentifier NULL,
    BatchId         uniqueidentifier NULL,
    SerialId        uniqueidentifier NULL,
    Name            nvarchar(150)    NOT NULL,           -- snapshot
    QtyMilli        bigint           NOT NULL,
    Price           bigint           NOT NULL,           -- kyats per unit
    CostSnapshot    bigint           NOT NULL,           -- kyats per unit at sale time
    LineTotal       bigint           NOT NULL,           -- (Price*QtyMilli + 500) / 1000, computed by server
    CreatedAt       datetime2(3)     NOT NULL,
    UpdatedAt       datetime2(3)     NOT NULL,
    DeletedAt       datetime2(3)     NULL,
    Version         rowversion       NOT NULL,
    CONSTRAINT PK_SaleLines PRIMARY KEY NONCLUSTERED (Id),
    CONSTRAINT FK_SaleLines_Sale FOREIGN KEY (SaleId) REFERENCES dbo.Sales (Id),
    CONSTRAINT FK_SaleLines_Product FOREIGN KEY (ProductId) REFERENCES dbo.Products (Id),
    CONSTRAINT FK_SaleLines_Serial FOREIGN KEY (SerialId) REFERENCES dbo.ProductSerials (Id),
    CONSTRAINT CK_SaleLines_Qty CHECK (QtyMilli > 0 AND Price >= 0 AND CostSnapshot >= 0)
);
CREATE CLUSTERED INDEX CX_SaleLines ON dbo.SaleLines (TenantId, CreatedAt);
CREATE INDEX IX_SaleLines_Sale ON dbo.SaleLines (SaleId);
CREATE INDEX IX_SaleLines_Product ON dbo.SaleLines (TenantId, ProductId) INCLUDE (QtyMilli, LineTotal, CostSnapshot);

CREATE TABLE dbo.Payments (
    Id              uniqueidentifier NOT NULL,
    TenantId        uniqueidentifier NOT NULL,
    SaleId          uniqueidentifier NOT NULL,
    Method          varchar(10)      NOT NULL,           -- cash|kbz|wave (never debt)
    Amount          bigint           NOT NULL,
    Received        bigint           NULL,               -- cash handed over
    CreatedAt       datetime2(3)     NOT NULL,
    UpdatedAt       datetime2(3)     NOT NULL,
    DeletedAt       datetime2(3)     NULL,
    Version         rowversion       NOT NULL,
    CONSTRAINT PK_Payments PRIMARY KEY NONCLUSTERED (Id),
    CONSTRAINT FK_Payments_Sale FOREIGN KEY (SaleId) REFERENCES dbo.Sales (Id),
    CONSTRAINT CK_Payments_Method CHECK (Method IN ('cash','kbz','wave')),
    CONSTRAINT CK_Payments_Amount CHECK (Amount >= 0 AND (Received IS NULL OR Received >= Amount))
);
CREATE CLUSTERED INDEX CX_Payments ON dbo.Payments (TenantId, CreatedAt);
CREATE INDEX IX_Payments_Sale ON dbo.Payments (SaleId);
GO

/* ---------------------------------------------------------------------
   6. Sync bookkeeping
   --------------------------------------------------------------------- */

/* Idempotency: every pushed unit (one client UnitOfWork) is applied once. */
CREATE TABLE dbo.ProcessedUnits (
    TenantId        uniqueidentifier NOT NULL,
    UnitId          uniqueidentifier NOT NULL,
    DeviceId        uniqueidentifier NOT NULL,
    Outcome         varchar(10)      NOT NULL,           -- applied|skipped|rejected
    ProcessedAt     datetime2(3)     NOT NULL,
    CONSTRAINT PK_ProcessedUnits PRIMARY KEY (TenantId, UnitId)
);

/* Real-world events (a sale, a payment) are never rejected. Anything odd is
   accepted and recorded here for the owner to review in the app/web. */
CREATE TABLE dbo.SyncIssues (
    Id              uniqueidentifier NOT NULL,
    TenantId        uniqueidentifier NOT NULL,
    Kind            varchar(30)      NOT NULL,           -- serialDoubleSold|negativeStock|duplicateBarcode|clockSkew|creditLimitExceeded|duplicateSerial
    EntityTable     varchar(40)      NOT NULL,
    EntityId        uniqueidentifier NOT NULL,
    Detail          nvarchar(400)    NOT NULL,
    DeviceId        uniqueidentifier NULL,
    ResolvedAt      datetime2(3)     NULL,
    CreatedAt       datetime2(3)     NOT NULL,
    UpdatedAt       datetime2(3)     NOT NULL,
    DeletedAt       datetime2(3)     NULL,
    Version         rowversion       NOT NULL,
    CONSTRAINT PK_SyncIssues PRIMARY KEY NONCLUSTERED (Id),
    CONSTRAINT FK_SyncIssues_Tenant FOREIGN KEY (TenantId) REFERENCES dbo.Tenants (Id)
);
CREATE CLUSTERED INDEX CX_SyncIssues ON dbo.SyncIssues (TenantId, CreatedAt);
GO

/* ---------------------------------------------------------------------
   7. Subscription (manual KBZPay/WavePay transfer + screenshot)
   --------------------------------------------------------------------- */

CREATE TABLE dbo.SubscriptionPayments (
    Id              uniqueidentifier NOT NULL,
    TenantId        uniqueidentifier NOT NULL,
    Amount          bigint           NOT NULL,
    Method          varchar(10)      NOT NULL,           -- kbz|wave
    Months          int              NOT NULL,           -- 1 or 12
    ScreenshotKey   varchar(200)     NULL,               -- Cloudflare R2 object key
    Status          varchar(10)      NOT NULL,           -- pending|approved|rejected
    ReviewedBy      nvarchar(80)     NULL,
    ReviewedAt      datetime2(3)     NULL,
    CreatedAt       datetime2(3)     NOT NULL,
    UpdatedAt       datetime2(3)     NOT NULL,
    Version         rowversion       NOT NULL,
    CONSTRAINT PK_SubscriptionPayments PRIMARY KEY NONCLUSTERED (Id),
    CONSTRAINT FK_SubscriptionPayments_Tenant FOREIGN KEY (TenantId) REFERENCES dbo.Tenants (Id),
    CONSTRAINT CK_SubscriptionPayments_Status CHECK (Status IN ('pending','approved','rejected'))
);
CREATE CLUSTERED INDEX CX_SubscriptionPayments ON dbo.SubscriptionPayments (TenantId, CreatedAt);
GO

/* ---------------------------------------------------------------------
   8. Pull indexes: every synced table is read with
      WHERE TenantId = @t AND Version > @cursor ORDER BY Version
   --------------------------------------------------------------------- */
CREATE INDEX IX_TenantFeatures_Pull  ON dbo.TenantFeatures  (TenantId, Version);
CREATE INDEX IX_Devices_Pull         ON dbo.Devices         (TenantId, Version);
CREATE INDEX IX_Products_Pull        ON dbo.Products        (TenantId, Version);
CREATE INDEX IX_ProductVariants_Pull ON dbo.ProductVariants (TenantId, Version);
CREATE INDEX IX_ProductBatches_Pull  ON dbo.ProductBatches  (TenantId, Version);
CREATE INDEX IX_ProductSerials_Pull  ON dbo.ProductSerials  (TenantId, Version);
CREATE INDEX IX_StockMovements_Pull  ON dbo.StockMovements  (TenantId, Version);
CREATE INDEX IX_Customers_Pull       ON dbo.Customers       (TenantId, Version);
CREATE INDEX IX_DebtEntries_Pull     ON dbo.DebtEntries     (TenantId, Version);
CREATE INDEX IX_Sales_Pull           ON dbo.Sales           (TenantId, Version);
CREATE INDEX IX_SaleLines_Pull       ON dbo.SaleLines       (TenantId, Version);
CREATE INDEX IX_Payments_Pull        ON dbo.Payments        (TenantId, Version);
CREATE INDEX IX_SyncIssues_Pull      ON dbo.SyncIssues      (TenantId, Version);
GO
