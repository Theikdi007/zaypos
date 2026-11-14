# ZayPOS Phase 3 — Offline database + sync client

Goal: replace the fake repositories with a real on-device database (Drift/SQLite),
record every unit of work in an outbox, and sync with the backend from
`docs/backend/README.md` §3. After Phase 3 the app works fully offline and two
phones of the same shop see each other's sales.

Server facts this design relies on (already built, tag `v0.2.0-backend`):
- `POST /api/v1/sync/push` — units, idempotent, outcome `applied | skipped | rejected`
- `GET /api/v1/sync/pull?cursor=&limit=` — rowversion cursor, includes soft-deleted rows
- `GET /api/v1/sync/limits` — text/number limits keyed like `products.name`
- Unit kinds: `checkout, voidSale, payDebt, upsertProduct, upsertCustomer, setFeatures, stockAdjust, restock`
- Auth: `/auth/otp|register|login|refresh|pin/reset`, JWT 15 min, refresh 90 days with 2-min grace
- `GET /me`, `GET /catalog/presets`, `GET/DELETE /devices`, `/subscription/*`
- Dev URL: `http://localhost:5076`

---

## 1. Principles

1. **The local database is the only thing screens read.** Screens never wait for the
   network. Network only moves rows between the local DB and the server.
2. **A local write and its outbox entry commit together.** One Drift transaction
   writes the rows *and* the outbox unit. There is no state where a sale exists
   locally but will never be pushed.
3. **Push before pull, in outbox order.** Units go up oldest first. A `rejected` unit
   **blocks** the outbox (later units may depend on it) and is shown to the owner.
   Nothing in the outbox is ever silently dropped.
4. **Pulled rows never overwrite newer local edits.** Mutable tables merge by
   `updatedAt` (same last-writer-wins rule as the server); ledgers are insert-or-ignore.
5. **Same limits as the server.** Form validation uses `/sync/limits` (cached), so the
   server never rejects data the app accepted.

---

## 2. Packages

| Package | Why |
|---|---|
| `drift`, `drift_flutter`, `drift_dev` + `build_runner` (dev) | SQLite with typed queries, streams, transactions, migrations |
| `dio` | HTTP with interceptors (auth header, single-flight refresh, retries) |
| `flutter_secure_storage` | refresh token, access token, local PIN hash |
| `connectivity_plus` | trigger sync when the network comes back |
| `cryptography` | PBKDF2 for the offline PIN check |

Use the latest stable versions. No other packages without asking.

---

## 3. Local database (Drift)

### 3.1 Synced tables
One Drift table per server table, **same column names and meaning** (camelCase in
Dart, the JSON names used by `/sync/push` and `/sync/pull`):
`tenants, tenantFeatures, devices, products, productVariants, productBatches,
productSerials, stockMovements, customers, debtEntries, sales, saleLines, payments,
syncIssues`.

- Ids: `TEXT` UUID. Money and milli-quantities: `INTEGER`. Times: `INTEGER` unix ms UTC.
- No `version` column on the phone (the cursor is stored once, §3.2).
- Indexes for what screens query: `stockMovements(productId)`, `debtEntries(customerId)`,
  `sales(createdAt)`, `saleLines(saleId)`, `products(barcode)`.

### 3.2 Local-only tables

```
outbox(
  seq        INTEGER PRIMARY KEY AUTOINCREMENT,  -- push order
  unitId     TEXT UNIQUE NOT NULL,
  kind       TEXT NOT NULL,                       -- server unit kind
  rowsJson   TEXT NOT NULL,                       -- {"sales":[…],"saleLines":[…],…}
  clientTime INTEGER NOT NULL,
  status     TEXT NOT NULL,                       -- pending | rejected
  attempts   INTEGER NOT NULL DEFAULT 0,
  lastError  TEXT,                                -- network/server error (retryable)
  rejectReason TEXT                               -- server reason (needs a human)
)
syncState(key TEXT PRIMARY KEY, value TEXT)      -- pullCursor, lastPushAt, lastPullAt, limitsJson, limitsEtag
```

### 3.3 Read models
Stock = `SUM(stockMovements.qtyMilli)` and debt balance = sum of ledger effects,
computed with Drift queries/views and exposed as `Stream`s. Batch stock = sum of
movements with that `batchId` (`ProductBatch.qtyMilli` becomes derived).

---

## 4. Unit of work + outbox

`UnitOfWork.run` gains the unit kind:

```dart
Future<T> run<T>(UnitKind kind, Future<T> Function() body);
```

`DriftUnitOfWork`:
1. Opens `db.transaction`.
2. Gives the body a `UnitRecorder` (zone value / scoped provider). Every Drift
   repository write calls `recorder.record(table, rowJson)`.
3. After the body succeeds, inserts **one** `outbox` row with all recorded rows, in the
   same transaction. If the body throws, nothing is written.
4. After commit, notifies the `SyncEngine` (debounced).

Services (`CheckoutService`, `VoidSaleService`, pay debt, add/edit product, add customer,
feature toggles, restock, stock adjust) pass the matching `UnitKind`.
Writes outside a unit of work are a bug: repositories assert a recorder is present.

`devices.lastSeq` for this device is recorded in the same checkout unit.

---

## 5. Sync engine

### 5.1 When it runs
- App start (after unlock), and every 5 minutes while in the foreground
- 2 s after any committed unit (debounced)
- When connectivity returns
- Pull-to-refresh on Dashboard and Sales history, and a "ယခု sync လုပ်မယ်" button in Settings

Only one sync runs at a time (single-flight). No background sync in v1.

### 5.2 One sync cycle

```
ensureFreshToken()
PUSH:
  loop:
    units = first 50 outbox rows with status = pending (stop at the first rejected)
    if none: break
    POST /sync/push
    for each result, in one Drift transaction:
      applied  → delete outbox row
      skipped  → delete outbox row AND delete that unit's rows from the local tables
                 (e.g. the sale was already voided on another phone; pull brings the truth)
      rejected → status = rejected, rejectReason = reason; STOP pushing
    network/5xx error → attempts++, lastError, back off (5 s, 30 s, 2 min, 10 min); STOP
PULL:
  loop:
    GET /sync/pull?cursor=<syncState.pullCursor>&limit=500
    one Drift transaction: merge every row (§5.3), then save the new cursor
    if !hasMore: break
```

A blocked outbox still pulls (the owner keeps seeing other phones' sales).

### 5.3 Merge rules for pulled rows

| Table | Rule |
|---|---|
| `sales, saleLines, payments, stockMovements, debtEntries, syncIssues` | insert or replace by id (server is truth; local copies are identical) |
| `sales.voidedAt` | take the server value |
| `products, productVariants, productBatches, customers, tenantFeatures, tenants` | replace only if `pulled.updatedAt >= local.updatedAt` **and** no pending outbox unit contains that id |
| `productSerials` | take the server row |
| own `devices` row | `lastSeq = max(local, pulled)` |
| `deletedAt` set | keep the row with `deletedAt` (screens hide it) |

### 5.4 First sign-in on a phone
Login on a new phone (or reinstall) → cursor `0` → full download with a progress
screen ("ဆိုင်ဒေတာ ဒေါင်းနေသည်… 1,240 / ?"). The app is usable only after the first
pull completes, so an empty phone never pushes on top of a shop it hasn't seen.

---

## 6. Auth and session

- Register (4 steps) and Login screens call the real endpoints. OTP step uses
  `POST /auth/otp`; in dev the code is printed in the backend console.
- `flutter_secure_storage`: `refreshToken`, `accessToken`, `accessExpiresAt`,
  `pinHash` (PBKDF2, random salt, 100k iterations), `tenantId`, `userId`, `deviceId`, `deviceCode`.
- `deviceId` is a UUID v7 generated **once per install** and stored securely; a reinstall is a new device.
- Dio interceptor: adds `Authorization`, refreshes 60 s before expiry; on `401` does
  **one** single-flight refresh and retries. If refresh fails with `401/403`
  (`device_revoked`), sign out to Login but **keep the outbox** and warn if it isn't empty.
- Offline unlock: the app opens with the 6-digit PIN checked against the local hash;
  no network needed. 5 wrong PINs → 15-min local lockout.
- Errors from the server are ProblemDetails with a stable `code`; map codes to Burmese messages
  (`otp_invalid`, `pin_locked`, `phone_registered`, `device_revoked`, `otp_rate_limited`, …).

---

## 7. Screens that change

| Screen | Change |
|---|---|
| Register step 3 | "ကြိုတင်စာရင်း" downloads `/catalog/presets` and saves them as products in one `upsertProduct` unit (no prices; owner fills them) |
| Dashboard | `OfflineSyncChip` shows real state: online + synced / `n` waiting / offline / **sync problem** |
| Settings | New "Sync" section: last sync time, pending count, "ယခု sync လုပ်မယ်", and **"စစ်ရန် (n)"** list of `syncIssues` and rejected units with their reason |
| Settings → Devices | list from `GET /devices`, owner can remove a lost phone |
| All forms | max lengths and rules from `/sync/limits` (fallback: bundled copy of the same values) |

Rejected-unit screen: shows what the unit was (e.g. "ပစ္စည်းအသစ် · ဆပ်ပြာ"), the server
reason, and two actions: **ပြင်ပြီး ပြန်ပို့မယ်** (edit the data, rebuild the unit, set pending)
and **Support ကို ပို့မယ်** (copy unit JSON to share via Viber). No "delete" button.

---

## 8. Dev setup (Mac + phones)

- Backend: `dotnet run --project backend/src/ZayPOS.Api --urls http://0.0.0.0:5076`
- API base URL via `--dart-define=API_BASE_URL=...`:
  - iOS simulator: `http://localhost:5076`
  - Android emulator: `http://10.0.2.2:5076`
  - Real phone on the same Wi-Fi: `http://<Mac LAN IP>:5076` (`ipconfig getifaddr en0`)
- Dev-only cleartext HTTP: Android `network_security_config` for debug builds only;
  iOS `NSAllowsLocalNetworking` in Info.plist. Release builds require HTTPS.

---

## 9. Tests

Unit/widget (no network, in-memory Drift):
- unit-of-work writes rows + exactly one outbox row; a throwing body writes neither
- push results: applied deletes, skipped deletes unit rows, rejected blocks later units, network error backs off
- merge rules of §5.3, including "pending local edit is not overwritten"
- cursor is saved only after a full page is merged
- single-flight refresh: 3 parallel 401s cause one `/auth/refresh`
- offline PIN unlock and lockout

Integration (optional, `integration_test/`, needs the backend running):
two simulated devices of one shop — A sells, B pulls and sees the sale; both sell the
same IMEI → B sees a `serialDoubleSold` issue.

---

## 10. Claude Code prompt (Phase 3)

Run from the repo root and paste:

````text
Implement Phase 3 exactly as docs/mobile/phase3-sync.md describes. Backend contracts are in docs/backend/README.md
and backend/src (read SyncContracts.cs, RowMapping.cs, SyncRows.cs and AuthContracts.cs for exact JSON shapes).

STEP 0 (backend, small): add POST /api/v1/sync/issues/{id}/resolve (owner only, sets ResolvedAt + UpdatedAt,
idempotent) with a test. Run dotnet test.

STEP 1: Drift database (§3) mirroring the server tables + outbox + syncState, with migrations (schemaVersion 1),
Drift repositories implementing the existing interfaces, DriftUnitOfWork with UnitRecorder (§4),
UnitKind added to every service call. Keep the fake repositories for tests only; the composition root now uses Drift.
All existing tests must still pass. STOP and show me a summary.

STEP 2: API client (dio) + auth/session (§6), Register/Login wired to the backend, offline PIN unlock.
STEP 3: SyncEngine (§5) + OfflineSyncChip + Settings sync section + "စစ်ရန်" list + rejected-unit screen (§7).
STEP 4: presets import, devices screen, /sync/limits in all form validators, dev setup (§8),
PIN reset flow (OTP → new PIN via /auth/pin/reset; reachable from Login and from the unlock screen,
also while locked out; on success the local PIN hash is replaced and the lockout cleared).

Write the tests in §9 as you go. Run `flutter analyze` and `flutter test` after every step, commit and push to a
branch `mobile-phase3`. Stop after STEP 1 and wait for my OK; after that continue step by step, stopping after each.
````
