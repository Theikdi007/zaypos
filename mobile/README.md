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

## Sign-in and local data

- API base URL: `--dart-define=API_BASE_URL=http://localhost:5076` (default).
  In dev the OTP code is printed in the backend console.
- Startup (`lib/features/auth/data/boot_state.dart`): a database without the
  install marker means a fresh install, so Keychain/Keystore leftovers are
  wiped and a new device id is made. A stored session opens on the PIN pad
  (offline PBKDF2 check; 5 wrong PINs → 15-minute lockout).
- Signing in to a shop other than the one whose data is on the phone wipes
  every local table except the outbox — and is refused (before any network
  call) while the outbox still has units (`lib/core/db/local_data.dart`).
  The same shop signing in again keeps everything.
- Debug builds only: "Demo ဆိုင်" on the Login screen opens the design's sample
  shop (never synced). Seeding throws in release builds and is never called there.
- Live auth test against a running backend: see `test/live_api_test.dart`.
