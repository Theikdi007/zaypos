# zaypos_app

ZayPOS Flutter app. Offline-first: screens read only the local Drift (SQLite)
database; every write is one unit of work recorded in the outbox
(see `docs/mobile/phase3-sync.md`).

## Local database (Drift)

- Schema: `lib/core/db/app_database.dart` (schemaVersion 1). Generated code
  (`app_database.g.dart`) is committed; after changing tables run
  `dart run build_runner build`.
- Schema change: bump `schemaVersion`, then `dart run drift_dev make-migrations`
  (snapshots live in `drift_schemas/`) and add the step in `onUpgrade`.
- Composition root: `lib/app/drift_overrides.dart`. The fake repositories in
  `lib/app/fake_*.dart` / `*/data/fake_*.dart` are for tests only
  (`test/helpers.dart`); Drift tests use an in-memory database
  (`test/drift_helpers.dart`).
- Debug builds seed the design's sample shop into a brand-new database
  (`lib/app/local_bootstrap.dart`) until sign-in lands (Phase 3 step 2).
