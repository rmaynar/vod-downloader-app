# VOD Downloader

A Flutter app for browsing and downloading movies and series from an
[Xtream Codes](https://en.wikipedia.org/wiki/IPTV) IPTV provider.

The app talks **directly to a provider you configure at runtime** — there is no backend
service to deploy or point at. You sign in with your provider's server URL, username, and
password; the app syncs the catalog into a local SQLite database, and browsing, searching,
filtering, and sorting all run against that local cache, so the app stays usable offline
and does not re-hit the provider for every screen.

Downloads run through a background download manager: they survive the app being
backgrounded, post progress notifications, support pause/resume via HTTP range requests,
and land in the device's public Downloads folder.

**Package:** `com.rmaynar.voddownloader` · **Version:** 1.0.0+1

## Features

- Multiple saved provider accounts, switchable in-app
- Movie and series catalogs with categories, search, sort, and infinite scroll
- Series detail view with per-season episode lists and per-episode download
- Download queue with pause / resume / cancel / retry, persisted across restarts
- Scales to real catalog sizes (~40k movies / ~11k series tested)
- Dark theme, phone and tablet layouts (bottom nav below 800dp, navigation rail above)

## Requirements

| Tool | Version |
| --- | --- |
| Flutter SDK | 3.47+ (developed on 3.47.3, stable channel) |
| Dart SDK | ^3.13.3 (bundled with Flutter) |
| JDK | 17 (Android build targets Java 17 / Kotlin JVM 17) |
| Android SDK | minSdk 24, compileSdk 36 — both inherited from the Flutter toolchain |
| Gradle | 9.3.1, via the committed wrapper (no manual install needed) |

Check your setup with `flutter doctor`.

## Quick start

```bash
git clone <repo-url>
cd vod-downloader-app
flutter pub get
flutter devices          # find your target's device id
flutter run -d <device-id>
```

On first launch the app opens a login screen. Enter your Xtream provider's server URL
(e.g. `http://provider.example.com:8080`), username, and password. The initial catalog
sync runs in the background and can take a while on large catalogs; subsequent launches
load instantly from cache and re-sync in the background once the cache is over 12 hours
old.

## Platform support

Only Android is a supported target. The other platform folders exist and carry the
correct bundle identifier, but they are not all usable — two plugins gate this:
`sqflite` (the catalog database, required at startup) and `background_downloader` (the
download queue).

| Platform | Status |
| --- | --- |
| **Android** | **Supported and verified** on an API 37 emulator. Full catalog + download queue. |
| iOS | Should build — both plugins support iOS — but has never been built or run. Unverified. |
| macOS | Starts and browses (sqflite works, entitlements are configured), but **downloads do not work**: `background_downloader` 9.6.1 declares no macOS implementation. |
| Linux / Windows | **Non-functional.** No `sqflite` implementation, so startup fails when the database opens. Scaffolding only. |
| Web | **Non-functional.** Neither plugin supports web. |

If you extend desktop support, those two plugins are the things to solve first.

## Building

### Android

```bash
flutter build apk --debug                  # debug APK
flutter build apk --release                # release APK (universal, all ABIs)
flutter build apk --release --split-per-abi # smaller per-architecture APKs
flutter build appbundle --release          # AAB for Play Store upload
```

Output lands in `build/app/outputs/flutter-apk/` (APK) or
`build/app/outputs/bundle/release/` (AAB).

Install a built APK on a connected device:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

#### Release signing

Release builds are signed with a real key only when `android/key.properties` exists.
That file is gitignored and personal to each machine — copy the committed template and
fill in your own details:

```bash
cp android/key.properties.template android/key.properties
# then edit storeFile / storePassword / keyAlias / keyPassword
```

Without it, `flutter build apk --release` still succeeds but **falls back to the debug
signing key**. That build runs fine locally, but cannot be installed as an update over a
properly-signed release and cannot be uploaded to a store. This fallback is deliberate so
fresh checkouts and CI build without secrets.

Generate a keystore if you don't have one:

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

### iOS (unverified)

```bash
flutter build ios --release          # requires a configured signing team in Xcode
flutter build ipa --release
```

Open `ios/Runner.xcworkspace` in Xcode to set the signing team first. Nothing here has
been exercised — treat it as a starting point, not a supported path.

### macOS (browsing only, no downloads)

```bash
flutter build macos --release
flutter run -d macos
```

The sandbox entitlements in `macos/Runner/*.entitlements` already grant outgoing network
access and read/write to the user's Downloads folder.

## Testing

```bash
flutter analyze                                       # expected: no issues
flutter test                                          # expected: all tests pass (114)
flutter test test/features/download_queue_test.dart   # a single file
flutter test test/features/download_queue_test.dart -n "pattern"   # a single test
```

The unit/widget suite runs entirely on the host — no device needed. Two platform-bound
dependencies are abstracted to make that possible: the database runs on
`sqflite_common_ffi` against a temp file, and the download queue's state machine is
driven through a `DownloadEngine` interface backed by a fake, so
`background_downloader` is never loaded.

### Integration tests (device required)

```bash
flutter test integration_test/app_flow_test.dart -d <device-id>
```

`app_flow_test.dart` drives the app end-to-end against a mock Xtream server it hosts
itself, so it needs no real account.

There is also a diagnostic test that logs in against a **real** provider. It holds no
credentials itself; real values come from a gitignored file:

```bash
cp integration_test/local/secrets.template integration_test/local/secrets.properties
# fill in your own account, then:
flutter test integration_test/local/real_login_test.dart -d <device-id> \
  --dart-define-from-file=integration_test/local/secrets.properties
```

Credentials are passed via `--dart-define-from-file` rather than read at runtime because
integration tests execute on the device and cannot read files from the host machine.
Never commit real credentials into a test file.

## Where downloads go

On Android, completed downloads are moved into the public Downloads folder
(`/storage/emulated/0/Download`) so other apps and a USB file browser can see them.
The app requests notification permission on first run to show download progress; denying
it does not stop downloads, only their notifications.

Downloads are deliberately **serialised, one at a time**. Xtream providers commonly cap an
account at a single simultaneous connection, and a second concurrent transfer is simply
refused by the server, so extra downloads queue and wait their turn.

## Security notes

- **Cleartext HTTP is permitted to any host.** Most Xtream providers serve plain HTTP and
  their hostnames are entered by the user at runtime, so a build-time domain allowlist
  isn't possible. Traffic to your provider can be observed or tampered with on a hostile
  network. See `android/app/src/main/res/xml/network_security_config.xml` for the full
  reasoning and residual risk.
- Provider credentials are embedded in download URLs by the Xtream protocol itself. The
  app redacts them from every error message, log line, and persisted record — if you add
  a new error path, route it through the existing redaction helpers.

## Project layout

```
lib/
  core/       models, Xtream HTTP client, SQLite service, theme, download service
  features/   auth, catalog, downloads, navigation, settings
              (UI under presentation/, state under providers/)
test/                 unit + widget tests (host-only)
integration_test/     on-device end-to-end tests
```

State management is Riverpod; routing is `go_router`. For architecture details,
invariants, and the reasoning behind the testing seams, see
[CLAUDE.md](CLAUDE.md). `PLAN.md` and `PLAN-ANDROID-STANDALONE.md` record the migration
from the original backend-proxy design to the current standalone app — note that they
are historical, and their references to a Node.js proxy no longer apply.
