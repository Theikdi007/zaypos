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

## Burmese text and money rules

- **Zawgyi (BUG-52):** free text typed on a Zawgyi keyboard (customer / product names, notes,
  addresses, categories, units, sizes, colours, batch numbers, quick-sale names, the shop name) is
  converted to Unicode before it is saved (`lib/core/text/myanmar_text.dart`, Google myanmar-tools'
  detector and converter, vendored under `lib/core/text/zawgyi/`). Search boxes accept either
  encoding. Valid Unicode is never altered. The server applies the same rule on sync push.
- **Unknown cost (BUG-53):** the template's sample cost / price are placeholder hints only. An empty
  cost is saved as 0 = unknown: profit shows "အရင်းမသိ" for it, and those lines are left out of the
  profit totals with a note "အရင်းမသိ N ခု မပါ". An empty price on a new product saves 0 and POS asks
  for the price at the first sale.
- **Open cart (BUG-57):** the cart is kept in the local database (`pos.openCart` in `sync_state`), so
  it survives Android killing the app in the background. Checkout clears it.

## Run on a phone over Wi-Fi (debug)

Debug builds may use plain HTTP to the Mac; release builds are HTTPS only. The app enforces it (BUG-55):
a release build with a non-https `API_BASE_URL` refuses to start and every request to a non-https URL is
refused, on Android and iOS (dart:io ignores the cleartext policy and ATS, so the platform settings alone are not enough).

- iOS: the "Debug Local Network" build phase (`ios/scripts/debug_local_network.sh`)
  adds `NSAllowsLocalNetworking` and `NSLocalNetworkUsageDescription` to the
  built Info.plist of Debug builds only.
- Android: `src/debug/res/xml/network_security_config.xml` (debug source set only)
  allows cleartext.

```sh
# Mac, terminal 1 — API on every interface (OTP codes are printed here)
cd backend && dotnet run --project src/ZayPOS.Api --urls http://0.0.0.0:5076

# Mac, terminal 2 — app on the phone, pointed at the Mac's Wi-Fi IP
cd mobile && flutter run -d <device-id> --dart-define=API_BASE_URL=http://$(ipconfig getifaddr en0):5076
```

Emulators: iOS simulator `http://localhost:5076`, Android emulator `http://10.0.2.2:5076`:

```sh
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:5076
```

Release APK (debug-signed until a keystore exists): `flutter build apk --release --dart-define=API_BASE_URL=https://<api-host>`.
Without an https URL the release app shows "ZayPOS ကို ဖွင့်လို့ မရပါ" and sends nothing (BUG-55; check with `tool/release_https_check.sh`).
See `docs/mobile/dev-setup.md` § Android emulator.
