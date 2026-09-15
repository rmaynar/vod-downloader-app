# 🎬 VOD Downloader

**Browse and download movies and series from your own
[Xtream Codes](https://en.wikipedia.org/wiki/IPTV) IPTV provider — no backend, no account
with anyone but your provider.**

You sign in with your provider's server URL, username, and password. The app pulls the
whole catalog into a local SQLite database, and from then on browsing, searching,
filtering, and sorting all run against that cache — so the UI stays instant and usable
offline instead of round-tripping to the provider for every screen. A background refresh
keeps the cache current once it passes 12 hours old.

Downloads run through a real background download manager: they survive the app being
backgrounded, post progress notifications, support pause and resume via HTTP range
requests, and land in the device's shared Downloads folder where any other app can see
them. Because Xtream providers commonly cap an account at one simultaneous connection,
downloads are deliberately serialised — one at a time, the rest queued.

**Package:** `com.rmaynar.voddownloader` · **Version:** 0.2.0+2 ·
**Platforms:** Android, macOS

The version is deliberately pre-1.0: the app is feature-complete and in daily use, but a
few behaviours have not been verified on real hardware yet (see *⚠️ Known gaps* below).
1.0.0 is reserved for when that list is clear.

## ✨ Features

### 📺 Catalog
- **Direct-to-provider** — configure any Xtream Codes provider at runtime; nothing to
  deploy or self-host
- **Offline-first browsing** — the full catalog lives in local SQLite; screens never wait
  on the network
- **Non-blocking sync** — a cached catalog renders immediately while the refresh runs in
  the background; only the very first sync shows a progress screen
- **Built for real catalogs** — tested at ~40k movies and ~11k series, with sorting and
  filtering pushed down into indexed SQL rather than done in Dart
- **Movies and series** — categories, full-text search, sort by name/rating/year, and
  infinite scroll
- **Series detail view** — per-season episode lists with per-episode download

### ⬇️ Downloads
- **Background download manager** — transfers continue when the app is backgrounded, with
  progress notifications on Android
- **Pause, resume, cancel, retry** — resume uses HTTP range requests, so an interrupted
  download picks up where it stopped
- **Persistent queue** — the queue and its progress survive app restarts
- **One connection at a time** — downloads are serialised to respect the single-connection
  limit Xtream providers typically enforce
- **Lands in shared storage** — finished files are moved to `/storage/emulated/0/Download`
  (Android) or `~/Downloads` (macOS), visible to every other app
- **Configurable destination** — pick the download location from Settings

### 👥 Accounts
- **Multiple saved providers** — store several accounts and switch between them from the
  top bar
- **Per-account catalogs** — every cached row is scoped to a source id derived from the
  provider URL and username, so accounts never see each other's data
- **Credentials never leak** — the Xtream protocol embeds your username and password in
  download URLs; the app redacts them out of every log line, error message, and persisted
  record

### 🎨 Interface
- **Responsive** — bottom navigation on phones, a navigation rail from 800dp, desktop nav
  links from 900dp
- **Dark theme** throughout
- **Branded** — a real app icon across the launcher, the Dock, and the in-app top bar

## 🧰 Requirements

| Tool | Version |
| --- | --- |
| Flutter SDK | 3.47+ (developed on 3.47.3, stable channel) |
| Dart SDK | ^3.13.3 (bundled with Flutter) |
| JDK | 17 (Android build targets Java 17 / Kotlin JVM 17) |
| Android SDK | minSdk 24, compileSdk 36 — both inherited from the Flutter toolchain |
| Gradle | 9.3.1, via the committed wrapper (no manual install needed) |
| Xcode | Required for macOS builds only |

The JDK, Android SDK, and Gradle rows apply to Android builds only — a macOS build needs
just Flutter and Xcode. Check your setup with `flutter doctor`.

## 🚀 Quick start

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

## 💻 Platform support

Android and macOS are both supported and tested. What gates the remaining platforms is
`sqflite`, the catalog database the app opens at startup: it ships implementations for
Android, iOS, and macOS only, and has no pure-Dart fallback.

| Platform | Status |
| --- | --- |
| **Android** | **Supported and verified** on an API 37 emulator. Full catalog + download queue. |
| **macOS** | **Supported and verified** by running a release `.app`: catalog, download queue, and files landing on disk. |
| iOS | Should build — every dependency supports iOS — but has never been built or run. Unverified. |
| Linux / Windows | **Non-functional.** No `sqflite` implementation, so startup fails when the database opens. Downloads would work; the database is the blocker. |
| Web | **Non-functional.** `sqflite` has no web implementation. |

Downloads work on desktop because `background_downloader` implements macOS, Linux, and
Windows in pure Dart (`DesktopDownloader`, dispatched at `base_downloader.dart:123`)
rather than through a platform plugin — so it is absent from the plugin registration
while still being fully functional. If you want Linux or Windows, `sqflite` is the only
thing to solve.

## 🔨 Building

### Android

```bash
flutter build apk --debug                  # debug APK
flutter build apk --release                # release APK (universal, all ABIs)
flutter build apk --release --split-per-abi # smaller per-architecture APKs
flutter build appbundle --release          # AAB for Play Store upload
```

Output lands in `build/app/outputs/bundle/release/` (AAB) or, for APKs, in two places:
Gradle writes `build/app/outputs/apk/release/vod-downloader-<version>[-<abi>].apk` — named
so the file is self-describing once it leaves the build directory — and the Flutter tool
additionally copies it to `build/app/outputs/flutter-apk/app-release.apk` under its own
fixed name. Either file is the same APK; prefer the named one when distributing.

Install a built APK on a connected device:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

#### Versioning

Both halves of `version:` in `pubspec.yaml` feed the Android build: `0.1.0` becomes
`versionName` (a display string, free to move however you like) and `+1` becomes
`versionCode`. Play requires `versionCode` to strictly increase on every upload, so bump
the build number for each distributed build — even a rebuild of an unchanged version.

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

### macOS

```bash
flutter build macos --release     # .app bundle
flutter run -d macos
```

The built bundle is at `build/macos/Build/Products/Release/VOD Downloader.app`.

The sandbox entitlements in `macos/Runner/*.entitlements` grant outgoing network access
and read/write to the user's Downloads folder — both are required, since the app
downloads from an arbitrary user-entered host and moves finished files into `~/Downloads`.

The bundle is **ad-hoc signed** (`CODE_SIGN_IDENTITY = "-"`, no team, not notarized). That
is fine locally, but Gatekeeper refuses to open a copy that arrived over the internet
until its quarantine attribute is cleared:

```bash
xattr -cr "/Applications/VOD Downloader.app"
```

### App icon

Every platform's icon set is generated from the single source image
`assets/vod-download-icon.jpeg`. After replacing that file, regenerate them:

```bash
dart run flutter_launcher_icons
```

`flutter_launcher_icons` is a dev dependency — it runs at generation time only and ships
in no build. Its configuration lives in the `flutter_launcher_icons:` block in
`pubspec.yaml`. The same image is also declared as a Flutter asset, because the in-app top
bar renders it directly and cannot reach the generated platform icons.

## 🧪 Testing

```bash
flutter analyze                                       # expected: no issues
flutter test                                          # expected: all tests pass (123)
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

## 📂 Where downloads go

Completed downloads are moved out of app-private storage into the platform's shared
Downloads folder, so other apps and a file browser can see them:

| Platform | Destination |
| --- | --- |
| Android | `/storage/emulated/0/Download` |
| macOS | `~/Downloads` |

On Android the app requests notification permission on first run to show download
progress; denying it does not stop downloads, only their notifications.

Downloads are deliberately **serialised, one at a time**. Xtream providers commonly cap an
account at a single simultaneous connection, and a second concurrent transfer is simply
refused by the server, so extra downloads queue and wait their turn.

## ⚠️ Known gaps

The app is feature-complete and in daily-usable shape, but these have not been confirmed
on real hardware and are the reason the version is still pre-1.0:

- **Task restoration across an app kill.** The persistence layer is on disk and unit-tested,
  but a kill/restore cycle has never been observed actually resuming a download.
- **The v1→v2 database migration as a real upgrade.** Covered by unit tests against a
  synthesised v1 database, never run against a database written by a pre-migration build
  of the app. This is the highest-risk item: a bad migration hits an existing user's
  cached catalog.
- **The Android progress notification appearing in the shade.** The code path runs; the
  notification itself has not been seen.
- **A full ~40k-item sync on Android without an ANR.** Chunked writes exist specifically
  to prevent this, and the sync has been exercised at that scale, but not on a
  low-end device.
- **iOS, entirely.** Never built or run.

Verified working: catalog sync and browsing at ~40k movies / ~11k series, and downloads
running to completion with files landing in the shared Downloads folder on both Android
and macOS.

## 🔐 Security notes

- **Cleartext HTTP is permitted to any host.** Most Xtream providers serve plain HTTP and
  their hostnames are entered by the user at runtime, so a build-time domain allowlist
  isn't possible. Traffic to your provider can be observed or tampered with on a hostile
  network. See `android/app/src/main/res/xml/network_security_config.xml` for the full
  reasoning and residual risk.
- Provider credentials are embedded in download URLs by the Xtream protocol itself. The
  app redacts them from every error message, log line, and persisted record — if you add
  a new error path, route it through the existing redaction helpers.

## 🗂️ Project layout

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
