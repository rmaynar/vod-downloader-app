# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this app is

`vod_downloader` — a Flutter app (Android is the primary target; other desktop
platforms build but are secondary) that browses and downloads movies/series from a
**user-configured Xtream Codes IPTV provider**. There is no backend: an earlier Node.js
proxy was deleted (commit `79fd7ca`), and the app now dials provider `player_api.php`
directly. Anything referring to a "backend proxy" or `10.0.2.2:3000` is stale history —
see `PLAN.md` / `PLAN-ANDROID-STANDALONE.md` for that migration's record, including its
list of still-unverified behaviours.

## Commands

```bash
flutter pub get
flutter analyze                              # must be clean (0 issues)
flutter test                                 # full unit/widget suite
flutter test test/features/download_queue_test.dart          # single file
flutter test test/features/download_queue_test.dart -n "pattern"   # single test
flutter run -d <device-id>
flutter build apk --debug
```

Integration tests need a real device/emulator:

```bash
flutter test integration_test/app_flow_test.dart -d <device-id>
# Real-provider login diagnostic; credentials come from a gitignored file:
flutter test integration_test/local/real_login_test.dart -d <device-id> \
  --dart-define-from-file=integration_test/local/secrets.properties
```

`integration_test/local/secrets.properties` is gitignored and personal-machine-only;
copy `secrets.template` beside it. Never commit credentials into a test file — the
`--dart-define-from-file` indirection exists because integration tests run on-device and
cannot read host files at runtime.

## Architecture

Layout is `lib/core/` (cross-cutting: models, network, database, theme, services) and
`lib/features/<feature>/` (auth, catalog, downloads, navigation, settings), with UI under
`presentation/` and state under `providers/`.

**State**: Riverpod (`flutter_riverpod`, `StateNotifier`-style, not codegen). The two
hubs are `catalogProvider` (`lib/features/catalog/providers/catalog_provider.dart`) and
`downloadQueueProvider` (`lib/features/downloads/download_queue_provider.dart`).

**Routing**: `go_router` in `lib/features/navigation/app_router.dart`. Auth is derived
state, not a separate provider — the redirect gate reads
`CatalogState.currentSourceId`, and `_RouterListenable` re-runs the redirect when that or
`isLoading` changes. Adding a route means adding it to **both** `appRouterProvider` and the
duplicated fallback `appRouter` getter in the same file.

**Data flow**: `XtreamClient` → `CatalogNotifier` → `DatabaseService` (SQLite) → UI. SQLite
is the source of truth for browsing; the provider is only hit on sync. `CatalogNotifier.initCatalog()`
loads cache first and then syncs in the background, so the UI is never blocked on the
network for an already-populated catalog (`isInitialSync` distinguishes first-ever sync
from a background refresh). Catalogs go stale after `CatalogNotifier.catalogStaleAfter`
(12h).

### Key invariants

- **One connection per account.** Xtream providers typically cap an account at 1
  simultaneous connection. `BackgroundDownloaderEngine` enforces this with a
  `MemoryTaskQueue` at `maxConcurrentDownloads = 1`, and downloads must be enqueued
  through that queue rather than `FileDownloader().enqueue`. Syncs and downloads competing
  for the same account is a real failure mode, not a theoretical one.
- **Source ids are derived, not assigned.** `deriveSourceId()` hashes the Xtream
  url+username (hence the direct `crypto` dependency). It is the primary key that scopes
  every catalog row (`sourceId` column on `movies`/`series`/categories), so changing the
  derivation invalidates every cached catalog.
- **Credentials never reach a log, message, or UI string.** Download URLs embed
  username/password. `DownloadService.redactCredentials()` and
  `DownloadQueueNotifier._redact()` scrub anything user-visible or persisted; keep new
  error paths running through them. `XtreamException.toString()` carries debug noise —
  UI must show `.message`.
- **Classify Xtream errors on `XtreamErrorKind`, never by matching on message text.**
  Message wording is for humans and changes freely; `isAuthFailure` is what decides
  "sign in again" vs. "check your connection".
- **Sync failures must not wipe the cache.** `syncCatalog` fetches categories/movies/series
  independently, applies only the slices that succeeded, and reports the rest via
  `state.error` — a total failure leaves SQLite and in-memory state untouched.

### Testing seams

Two things cannot run under plain `flutter test`, and both are deliberately abstracted:

- **sqflite** needs a platform channel. Tests use `sqflite_common_ffi` plus
  `DatabaseService.testDbPath` / `resetForTest()` (both `@visibleForTesting`) to point the
  singleton at a temp database. Follow the setup in `test/core/database_service_test.dart`.
- **`background_downloader`** needs a real device. Every plugin call lives behind the
  `DownloadEngine` interface in `lib/features/downloads/download_engine.dart`;
  `DownloadQueueNotifier` never imports the plugin, which is what lets
  `test/features/download_queue_test.dart` drive the whole state machine against
  `FakeDownloadEngine`. Keep plugin types out of the notifier. (The plugin's own
  `DownloadTask` collides with our model of the same name — it is imported as `bg` inside
  the engine file only.)

### Gotchas worth knowing before you touch them

- `DatabaseService` is at schema version 2; `movies`/`series` carry `rating`/`year` as
  indexed columns extracted from the JSON `data` blob at write time so 40k-item catalogs
  can sort in SQL. Adding a sort key means a migration plus an index, not a Dart-side sort.
- Bulk writes chunk at `_writeChunkSize` (2000) inside one outer transaction to avoid
  blocking the isolate long enough to ANR.
- The engine uses `FileDownloader().registerCallbacks(...)`, **not** `FileDownloader().updates`.
  The `updates` stream hangs off a mutable controller the plugin swaps out, which silently
  stops delivering events — see the comment in `download_engine.dart:initialize()`.
- Catalogs of ~40k movies / ~11k series are the realistic scale; list parsing runs through
  `compute()` isolates in `XtreamClient`, which is why its list normalisers are top-level
  functions.

## Conventions

Existing code carries unusually dense explanatory comments — including on `pubspec.yaml`
dependencies, which record *why* a package is a direct dependency. Match that: explain the
reasoning behind a non-obvious choice rather than restating the code.

<!-- rtk-instructions v2 -->
## Token Optimization (RTK)
- Prefix heavy terminal commands with `rtk` when running arbitrary inspections (e.g., `rtk git log`, `rtk cargo test`).
- Keep command outputs concise and favor quiet flags (`--quiet`, `-q`) alongside RTK filtering.
# Command output

Command output here is condensed to save tokens, keeping every signal and
dropping costly noise. Treat it as the complete result: run commands
normally, and batch related commands into one call to avoid extra turns.
Truncated results state their recovery path in their own output. Re-run a
command as `rtk proxy <cmd>` only when its result is unusable: empty when
output was clearly expected, contradicting its exit code, or garbled.
<!-- /rtk-instructions -->
