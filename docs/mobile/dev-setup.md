# ZayPOS — dev setup: API on the Mac, app on a real iPhone over Wi-Fi

Debug builds may talk plain HTTP to the Mac; release builds are HTTPS only
(docs/mobile/phase3-sync.md §8).

- **iOS:** the Xcode build phase *Debug Local Network*
  (`mobile/ios/scripts/debug_local_network.sh`) adds `NSAllowsLocalNetworking`
  and `NSLocalNetworkUsageDescription` to the **built** Info.plist of Debug builds
  only. `ios/Runner/Info.plist` itself does not contain them, so Release/Profile
  keep App Transport Security fully on.
- **Android:** `mobile/android/app/src/debug/res/xml/network_security_config.xml`
  (debug source set only) allows cleartext; release builds have no such config.

## One-time setup (iPhone)

1. Connect the iPhone with a cable once. On the phone:
   **Settings → Privacy & Security → Developer Mode → On**, then restart it and confirm.
2. Open the project and choose your signing team:
   ```sh
   open ~/Developer/ZayPOS/mobile/ios/Runner.xcworkspace
   ```
   Runner target → **Signing & Capabilities** → Team.
3. In Xcode: **Window → Devices and Simulators** → select the iPhone →
   tick **Connect via network**. Unplug the cable; the iPhone and the Mac must be
   on the **same Wi-Fi**.
4. The dev SQL Server container must be running (`docker ps` shows `zaypos-sql` on
   `127.0.0.1:1433` — loopback only, see docs/backend/README.md §6; only the API is
   reachable from the phone), and the
   database must have every migration (otherwise e.g. the preset catalog is empty):
   ```sh
   cd ~/Developer/ZayPOS/backend
   dotnet tool restore
   dotnet ef migrations list  --project src/ZayPOS.Infrastructure --startup-project src/ZayPOS.Api   # "(Pending)" = not applied
   dotnet ef database update  --project src/ZayPOS.Infrastructure --startup-project src/ZayPOS.Api
   ```

## Every time

**Terminal 1 — the API**, listening on every interface (not only localhost):

```sh
cd ~/Developer/ZayPOS/backend
dotnet run --project src/ZayPOS.Api --urls http://0.0.0.0:5076
```

If macOS asks whether `dotnet` may accept incoming network connections, click **Allow**.
OTP codes are printed here: `DEV SMS to +959…: ZayPOS code: 123456`.

**Terminal 2 — the app on the iPhone**, pointed at the Mac's Wi-Fi IP:

```sh
cd ~/Developer/ZayPOS/mobile
flutter devices                                   # find the iPhone's device id
flutter run -d <iPhone-device-id> \
  --dart-define=API_BASE_URL=http://$(ipconfig getifaddr en0):5076
```

`ipconfig getifaddr en0` prints the Mac's Wi-Fi IP (e.g. `192.168.100.198`); it can
change between networks, so keep the `$(…)` form.

**On the iPhone:** when iOS asks *"ZayPOS would like to find and connect to devices
on your local network"*, tap **Allow**. If you tap *Don't Allow*, every request
fails until you enable it in **Settings → Privacy & Security → Local Network**.

A debug build only runs while started from `flutter run` (opening it from the home
screen later does not work); run the command again.

## Check the connection

From the Mac (and from Safari on the iPhone) this must answer JSON:

```sh
curl http://$(ipconfig getifaddr en0):5076/api/v1/sync/limits
```

If the Mac answers but the iPhone doesn't: same Wi-Fi? macOS firewall allows `dotnet`?
Local Network permission on?

## Other targets

| Target | `API_BASE_URL` |
|---|---|
| iOS simulator | `http://localhost:5076` (the default) |
| Android emulator | `http://10.0.2.2:5076` |
| Android phone on the same Wi-Fi | `http://$(ipconfig getifaddr en0):5076` |

## Live tests against the running API

```sh
# 1. ask for a register OTP for a NEW phone number; read the code in terminal 1
curl -X POST http://127.0.0.1:5076/api/v1/auth/otp -H 'content-type: application/json' \
  -d '{"phone":"+959790000123","purpose":"register"}'
# 2. run (one OTP per run; each run registers a new shop)
cd ~/Developer/ZayPOS/mobile
ZAYPOS_LIVE_API=http://127.0.0.1:5076 ZAYPOS_LIVE_PHONE=+959790000123 ZAYPOS_LIVE_OTP=<code> \
  flutter test test/live_sync_test.dart      # two phones, one shop (§9 integration)
```

`test/live_api_test.dart` (auth round-trip) takes the same variables — use a different
phone number for each file.

STEP 4 (limits = server, preset import, removing a phone, PIN reset) asks for its own
codes; give it the file the API's console output goes to:

```sh
dotnet run --project src/ZayPOS.Api --urls http://127.0.0.1:5076 > /tmp/zaypos-api.log   # terminal 1
ZAYPOS_LIVE_API=http://127.0.0.1:5076 ZAYPOS_LIVE_LOG=/tmp/zaypos-api.log \
  flutter test test/live_step4_test.dart
```

## Updating the bundled form rules

`mobile/assets/sync/limits.json` is a copy of `GET /api/v1/sync/limits` (used offline
before the first refresh). After changing `SyncLimits.cs`:

```sh
curl -s http://127.0.0.1:5076/api/v1/sync/limits | python3 -m json.tool --indent 2 \
  > ~/Developer/ZayPOS/mobile/assets/sync/limits.json
```

`test/live_step4_test.dart` fails if the copy and the server differ.
