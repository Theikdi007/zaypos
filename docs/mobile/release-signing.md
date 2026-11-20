# Android release signing

The upload keystore lives **outside the repo**: `~/zaypos-secrets/zaypos-upload.jks`, alias `zaypos`.
Back it up (with its password) somewhere other than this Mac: losing it means a new key, and installed
copies cannot update to an APK signed by a different key.

## key.properties

`mobile/android/key.properties` (gitignored by `mobile/android/.gitignore`; never commit it, never paste
its passwords into a chat, a script or a command line):

```properties
storeFile=/Users/<you>/zaypos-secrets/zaypos-upload.jks
storePassword=<keystore password>
keyAlias=zaypos
keyPassword=<key password; the same as storePassword for a PKCS12 keystore>
```

- `storeFile` may also be written `~/zaypos-secrets/zaypos-upload.jks` (`app/build.gradle.kts` expands `~`).
- No quotes, no spaces around `=`. A backslash, `:`, `=` or `#` in a password must be escaped with `\`
  (Java properties format).
- `chmod 600 mobile/android/key.properties`.

`app/build.gradle.kts` uses it for every release build (`flutter build apk|appbundle --release`,
`flutter run --release`). With no `key.properties`, a release build **fails** ("Release build needs
android/key.properties") instead of falling back to the debug key. Debug and profile builds are not
affected.

## Google Sign-In needs the release fingerprints

Google's Android OAuth client is bound to package + signing certificate. A release APK signed by the upload
key signs in with Google only after its SHA-1 (and SHA-256) are added in Firebase → Project settings →
Android app `app.zaypos` → **Add fingerprint** (docs/backend/auth-google.md §6). Get them with (keytool asks
for the keystore password itself):

```sh
keytool -list -v -keystore ~/zaypos-secrets/zaypos-upload.jks -alias zaypos
```

If the app is later distributed through Google Play with Play App Signing, also add the **app signing key**
fingerprints from Play Console → Setup → App signing (Play re-signs the APK with that key).

Check a built APK is signed by the upload key and not the debug key:

```sh
"$ANDROID_HOME"/build-tools/*/apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

The certificate's SHA-256 must match the keytool output above, not `~/.android/debug.keystore`.
