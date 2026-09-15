# Standalone Android VOD Downloader — Parallel Migration Plan

---

## STATUS: implementation complete (2026-09-15)

All batches landed on `standalone-xtream-migration`. `flutter analyze` is clean,
**100 tests pass** (from 19 at baseline), the debug APK builds, and the app runs on an
API 37 emulator.

**Verified on-device**
- App launches, renders, and the backend proxy URL field is gone from login.
- A login against an unreachable server reports
  `Could not connect to Xtream server at http://127.0.0.1:1` — a direct dial with no
  backend involved, no exception class name leaked, no credentials in the message.
- `moveToSharedStorage` places completed downloads in `/storage/emulated/0/Download`
  at full size (checked with `adb`, not from the library's return value).
- Pause/resume resumes at the correct byte offset (`Range: bytes=17825792-`).

**Known-unverified — needs a real Xtream account**
- Login against a live provider, and the ~40k-item sync completing without ANR.
- A real movie/episode download running to completion and landing in Downloads.
- Task restoration across an app kill (infrastructure is on disk; a kill/restore cycle
  was never observed succeeding).
- The progress notification actually appearing in the shade.
- The v1→v2 database migration against a database written by the pre-migration build
  (covered by unit tests, never exercised as a real app upgrade).

**Deliberately out of scope**
- iOS/macOS/Linux/Windows/web still carry the old bundle identifiers; only the Android
  target was renamed.
- `series_screen.dart` has a pre-existing header-row overflow at narrow widths, found
  while working but not introduced by this migration. Not fixed.

---

> On approval this document is also written into the repo as `PLAN-ANDROID-STANDALONE.md`
> (plan mode only permits editing this scratch plan file). The existing `PLAN.md`
> describes the completed backend-coupled phase and gets a pointer to this one.

## Context

`vod-downloader-app` is the Flutter port of the React app at `/Users/rmaynar/workspace/nodecast-catalog`.
The port is functionally complete — login, catalog grid, search/filter/sort, series details with
seasons/episodes, SQLite caching, settings, dark theme — and was smoke-tested on an emulator against
a real catalog (40k movies / 11k series).

**But it is not self-sufficient.** Every network call goes through the `nodecast-tv` Node proxy at
`http://10.0.2.2:3000`:

| Concern | Current path | File |
|---|---|---|
| List/create sources | `GET/POST /api/sources` | `lib/core/network/api_client.dart:119,272` |
| Categories & streams | `GET /api/proxy/xtream/:sourceId/*` | `api_client.dart:137-231` |
| Series episodes | `GET /api/proxy/xtream/:sourceId/series_info` | `api_client.dart:235` |
| File download | `GET /api/download/:sourceId/:type/:itemId` | `lib/core/services/download_service.dart:55` |

The `sourceId` the whole app keys on is a **backend-assigned integer**, and the Xtream password is
held by the backend, not used by the app. Without the Node server running, login fails and the
catalog stays empty.

**Goal:** the Android app talks straight to the Xtream Codes provider (`player_api.php` +
direct stream URLs), owns its own source identity and credentials, and ships a real download
manager. The Node proxy is removed entirely.

### Decisions taken (confirmed with the user)

1. **Remove the proxy backend entirely** — no optional fallback mode.
2. **Downloads land in the public Downloads/Movies folder**, visible to the system Downloads app
   and surviving uninstall.
3. **Full download manager**: queue, live progress, pause/resume, cancel, retry, foreground
   service + progress notification.
4. **Credentials stay in plaintext SharedPreferences** — no `flutter_secure_storage`. Accepted
   trade-off for a personal-use app. (Worth knowing: the password is now also embedded in every
   download URL, so it will appear in notification payloads and any logged URL. Task A2/B2 include
   redacting it from logs and error strings.)

### Reference: the Xtream contract

Taken from the working Node implementation, `nodecast-tv/server/services/xtreamApi.js` and
`nodecast-tv/server/routes/download.js:34-50`. Mirror it exactly.

```
API:     {base}/player_api.php?username={u}&password={p}[&action={a}][&{params}]
actions: (none) → auth   get_vod_categories   get_vod_streams[&category_id]
                          get_series_categories  get_series[&category_id]
                          get_series_info&series_id={id}
Stream:  {base}/movie/{u}/{p}/{stream_id}.{container}
         {base}/series/{u}/{p}/{episode_id}.{container}
```

`{base}` is the provider URL with trailing slashes stripped. Two behaviours that bite:

- **Bad credentials return HTTP 200** with `{"user_info":{"auth":0}}`. Never trust the status code —
  check `user_info.auth == 1` and `user_info.status == "Active"`.
- Providers commonly **302-redirect** stream URLs to a CDN, so the downloader must follow redirects.

The good news: the proxy passed Xtream's JSON through essentially unchanged, so
`MediaItem.fromJson`, `CategoryItem.fromJson` and `SeriesDetails.fromJson`
(`lib/core/models/`) already parse the real provider shapes and need no changes.

---

# How this plan is executed in parallel

Work is grouped into **batches of at most three concurrent Sonnet 5 agents**, running in one shared
working tree. Every task inside a batch owns a **disjoint set of files**. The orchestrating session
dispatches one batch, waits for all of it to report, reviews, then dispatches the next.

| Batch | Tasks | Gate before dispatch |
|---|---|---|
| 0 | Baseline (solo) | — |
| 1 | **A1** Xtream client · **A3** SQLite v2 · **A5** downloader spike | Batch 0 committed, contracts frozen |
| 2 | **A2** Android shell · **A4** catalog perf | — (independent; may overlap batch 1 if agent budget allows) |
| 3 | **B1** catalog+login · **B2** download URLs · **B3** settings | A1 landed |
| 4 | **B4** series info · **C1** queue engine · **C4** routing+nav | A3, A5, B2 landed |
| 5 | **C2** downloads screen · **C3** live progress in cards/modal | C1 contract landed; C3 also needs B4 |
| 6 | **D1** delete backend → **D2** package rename → **D3** verify | strictly serial, one at a time |

**Rules for concurrent agents**

1. **Never edit a file you do not own.** The owned-files column below is exhaustive. If a task needs
   a change in someone else's file, it stops and reports rather than editing.
2. **Code against the frozen contracts** in the next section, not against whatever currently exists.
   Contracts are fixed before Wave A starts, which is what lets Wave B build against a client Wave A
   is still writing.
3. **Each task lands its own commit** and leaves `flutter analyze` no worse than it found it. The
   tree will not fully compile between Wave B and Wave D — that is expected and called out.
4. Run `flutter test <your own test file>` rather than the full suite while waves are in flight.

`pubspec.yaml`, `AndroidManifest.xml` and `database_service.dart` are each owned by exactly one task
for the whole plan, because they are the natural collision points.

## Contracts — freeze these before any agent starts

Pin these names, paths and signatures first; they are the seams the waves depend on.

```dart
// lib/core/network/xtream_client.dart            [owned by A1]
class XtreamException implements Exception { final String message; final int? statusCode; }
class XtreamUserInfo {
  final bool auth; final String status; final DateTime? expiresAt;
  final int? maxConnections; final bool isTrial;
}
class XtreamClient {
  XtreamClient({required String baseUrl, required String username,
                required String password, Dio? dio});
  Future<XtreamUserInfo> authenticate();
  Future<List<CategoryItem>> getVodCategories(String sourceId);
  Future<List<CategoryItem>> getSeriesCategories(String sourceId);
  Future<List<MediaItem>>    getVodStreams(String sourceId, {String? categoryId});
  Future<List<MediaItem>>    getSeries(String sourceId, {String? categoryId});
  Future<SeriesDetails>      getSeriesInfo(String seriesId);
  String buildStreamUrl({required String type,        // 'movie' | 'series'
                         required String id, required String container});
}

// lib/core/models/xtream_source.dart              [owned by A1]
String normalizeServerUrl(String raw);              // adds http://, strips trailing /
String deriveSourceId(String url, String username); // sha1('$url|$username') → 16 hex chars

// lib/core/providers/xtream_provider.dart         [owned by A1]
/// Null when no account is active. Built from catalogProvider's currentAccount.
final xtreamClientProvider = Provider<XtreamClient?>((ref) => …);

// lib/features/downloads/download_task.dart       [owned by C1]
enum DownloadStatus { queued, running, paused, complete, failed, canceled }
class DownloadTask {
  final String id;        // == Xtream stream/episode id
  final String sourceId; final String title; final String fileName;
  final DownloadStatus status; final double progress;  // 0.0–1.0
  final int? bytesTotal; final String? localUri; final String? error;
}

// lib/features/downloads/download_queue_provider.dart   [owned by C1]
final downloadQueueProvider =
    StateNotifierProvider<DownloadQueueNotifier, List<DownloadTask>>(…);
/// Progress for one item, for cards/modals. Null when not queued.
final downloadTaskProvider = Provider.family<DownloadTask?, String>(…);
// DownloadQueueNotifier: enqueueMovie / enqueueEpisode / pause / resume / cancel / retry

// SQLite                                          [owned by A3]
// _dbVersion 1 → 2, add onUpgrade, add table:
//   downloads(id TEXT PRIMARY KEY, sourceId TEXT, title TEXT, fileName TEXT,
//             status TEXT, progress REAL, bytesTotal INTEGER, localUri TEXT,
//             error TEXT, createdAt INTEGER)

// Route                                           [owned by C4]
// '/downloads' → DownloadsScreen, in both the bottom bar and the ≥800dp rail
```

---

# Wave 0 — Baseline (solo, blocks everything)

- [ ] `flutter pub get && flutter analyze && flutter test` — confirm the documented "0 issues,
      19/19 passing" starting point.
- [ ] `flutter devices` — confirm an Android emulator or device is attached.
- [ ] **Commit the tree.** The repo has *no commits yet* (everything is untracked). A baseline
      commit is what makes every parallel task reviewable as a diff, so this is not optional.
- [ ] Freeze the contracts above into the repo as empty stub files, so Wave B agents can import
      them and analyze cleanly while Wave A fills them in.

# Wave A — batches 1 and 2

*Batch 1: A1, A3, A5. Batch 2: A2, A4.*

| # | Task | Owns |
|---|---|---|
| A1 | Xtream client + source identity | `lib/core/network/xtream_client.dart`, `lib/core/models/xtream_source.dart`, `lib/core/providers/xtream_provider.dart`, `test/core/xtream_client_test.dart` |
| A2 | Android shell hardening | `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/res/xml/network_security_config.xml`, `android/key.properties` |
| A3 | SQLite v2 + write-path perf | `lib/core/database/database_service.dart`, `test/core/database_service_test.dart` |
| A4 | Catalog screen perf | `lib/features/catalog/presentation/movies_screen.dart`, `lib/features/catalog/presentation/series_screen.dart` |
| A5 | `background_downloader` spike | `pubspec.yaml`, throwaway scratch harness |

### A1 — Xtream client + source identity

- [ ] Implement `XtreamClient` per the contract. Port the list-normalising and error-mapping
      helpers from `api_client.dart:83-115` (`_normalizeList`, `_handleError`) rather than
      rewriting them; rename the exception to `XtreamException`.
- [ ] `authenticate()` throws a typed error when `user_info` is missing, `auth != 1`, or
      `status != "Active"` — **at HTTP 200**. Surface `exp_date`, `max_connections`, `is_trial`.
- [ ] Category/stream/series methods reuse the existing `CategoryItem.fromJson`,
      `MediaItem.fromJson` and `SeriesDetails.fromJson` unchanged.
- [ ] Large-payload handling: `get_vod_streams` on a 40k catalog is a ~40 MB body. Request it with
      `ResponseType.plain` and run `jsonDecode` + the model map inside `compute()` so the UI isolate
      never blocks. Raise `receiveTimeout` to ~180s for the two bulk calls.
- [ ] `deriveSourceId` = `sha1('$normalizedUrl|$username')` truncated to 16 hex chars — local,
      deterministic, stable across reinstalls, no backend needed to mint it. `normalizeServerUrl`
      lifts the logic currently inline at `catalog_provider.dart:429-433`.
- [ ] Tests using the existing `MockAdapter` pattern (`test/core/api_client_test.dart:7-21`): URL
      construction per action, `auth: 0` rejection, list-vs-`{data:[…]}` normalisation, stream-URL
      building, series_info parse, `deriveSourceId` stability.

### A2 — Android shell hardening

- [ ] `applicationId`/`namespace` are still `com.example.nodecast_catalog_flutter`
      (`build.gradle.kts:8,19`) and the launcher label is `nodecast_catalog_flutter`
      (`AndroidManifest.xml:8`). Set the real package name and label here. *(The matching **Dart**
      package rename is deliberately deferred to D2 — it touches every file in the repo.)*
- [ ] Release signing: `buildTypes.release` still signs with the debug key
      (`build.gradle.kts:33-38`). Add a keystore-backed `signingConfig` from a gitignored
      `key.properties`.
- [ ] Add the permissions Wave C will need, **now**, so C never has to touch this file:
      `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`. Drop
      `WRITE_EXTERNAL_STORAGE`/`READ_EXTERNAL_STORAGE` (`AndroidManifest.xml:4-5`) — MediaStore
      handles the writes.
- [ ] Replace app-wide `usesCleartextTraffic="true"` with a scoped `network_security_config.xml`
      (most Xtream providers are plain HTTP, so cleartext must stay permitted — just not globally).

### A3 — SQLite v2 + write-path performance

- [ ] Bump `_dbVersion` to 2 (`database_service.dart:21`) and add the `onUpgrade` handler the class
      currently **lacks** — existing installs already hold a v1 database, so a bare version bump
      would crash them.
- [ ] Add the `downloads` table per the contract, plus CRUD used by C1.
- [ ] `saveMovies`/`saveSeries` (`:108`, `:147`) `jsonEncode` ~51k items on the UI isolate inside a
      single transaction. Chunk the batch (~2k rows per `batch.commit`) and accept pre-encoded row
      maps so the caller can build them in an isolate.
- [ ] Add a SQL-backed `searchMedia(sourceId, query, categoryId, sort, limit, offset)` using the
      existing `idx_movies_source` / `idx_movies_cat` indexes — A4 and a later paging change consume it.
- [ ] Tests: v1→v2 migration preserves existing rows; chunked insert round-trips 5k items.

### A4 — Catalog screen performance

- [ ] `movies_screen.dart:87-112` filters **and sorts the full 40k-item list inside `build()`**, so
      every keystroke re-sorts everything. Debounce the search controller (~250ms) and memoise the
      result per (query, category, sort) key. `series_screen.dart` has the same shape.
- [ ] Keep the in-memory path for now; leave a clearly-marked seam for swapping in A3's
      `searchMedia` if a real device still struggles.

### A5 — `background_downloader` spike *(feeds C1; can run in a git worktree)*

- [ ] Add `background_downloader` to `pubspec.yaml`. It is the recommendation because one dependency
      covers the Android foreground service, progress notifications, pause/resume via HTTP Range, a
      persistent task database, and `moveToSharedStorage(SharedStorage.downloads)` for the
      public-folder requirement.
- [ ] **Validate against a real provider before C1 builds on it**: does pause/resume actually work
      on a 302-redirecting Xtream stream URL, and does `moveToSharedStorage` land the file in the
      system Downloads app? Confirm the current API against pub.dev — do not code from memory.
- [ ] Report a go/no-go. The fallback is Dio + `flutter_local_notifications` + `media_store_plus`
      plus a hand-written queue, which is materially more work and changes C1's shape.

# Wave B — batch 3 (B1, B2, B3), then B4 in batch 4 *(needs A1)*

These four rewire the app onto `xtreamClientProvider`. They touch disjoint files. B4 is small and
rides along in batch 4 so batch 3 stays at three agents. The tree will not fully compile until Wave
D removes the dead backend code — that is expected.

| # | Task | Owns |
|---|---|---|
| B1 | Catalog provider + login | `lib/features/catalog/providers/catalog_provider.dart`, `lib/features/auth/presentation/login_screen.dart` |
| B2 | Download URLs | `lib/core/services/download_service.dart`, `test/core/download_service_test.dart` |
| B3 | Settings provider card | `lib/features/settings/presentation/settings_screen.dart` |
| B4 | Series info call | `lib/features/catalog/presentation/widgets/media_details_modal.dart` |

### B1 — Catalog provider + login

- [ ] `loginWithXtream` (`catalog_provider.dart:411-505`): delete the `getSources()` match and the
      `createSource()` registration. New flow — `normalizeServerUrl` → `authenticate()` →
      `deriveSourceId` → persist account **with password** to SharedPreferences + the `sources`
      table → `syncCatalog(forceSync: true)`.
- [ ] `initCatalog` (`:135-265`): drop the `_api.getSources()` merge at `:166-191`. Saved accounts
      come from SharedPreferences with the SQLite `sources` table as fallback — that fallback
      already exists at `:161-163`.
- [ ] `syncCatalog` (`:328-408`): remove the `_api.syncSource(targetId)` call at `:349-356`;
      `forceSync` now simply means "ignore cache and refetch". Keep the four-step progress
      messaging and the SQLite write-through, now calling A3's chunked writers.
- [ ] `login_screen.dart`: surface the `auth: 0` / expired-account errors distinctly from network
      failures — this is the most common real-world failure and today it would read as a hang.
- [ ] Leave the `export … show apiClientProvider` line at `:15` in place; **D1 removes it.**

### B2 — Download URLs

- [ ] Replace `buildDownloadUrl` (`download_service.dart:40-56`) — it emits
      `{proxy}/api/download/{sourceId}/{type}/{itemId}?container=…&name=…` and must now emit the
      direct Xtream stream URL via `XtreamClient.buildStreamUrl`. The `name` query param disappears;
      `sanitizeFileName` (`:126`) becomes the sole namer.
- [ ] `getDownloadUrlForMedia` (`:59`) / `getDownloadUrlForEpisode` (`:80`) take the active account
      instead of a bare `sourceId`, so they can reach username/password. Keep the
      `"{Series} S01E02 - {Title}"` naming from `:90-91`.
- [ ] Drop the `dynamic _apiClient` field (`:13`) and the `ApiConstants.defaultBaseUrl` fallback
      (`:35`) — the service depends on the account, not on a host.
- [ ] Send `User-Agent: Mozilla/5.0` and keep `followRedirects: true` (`:154`); the Node proxy did
      both (`download.js:104`) and some providers reject default clients.
- [ ] Add a `redactCredentials(url)` helper and use it in every thrown/logged message.
- [ ] Update `test/core/download_service_test.dart` to the new URL shape.

### B3 — Settings provider card

- [ ] Delete the "Backend Proxy URL" card and its `_handleTestConnection` / `_handleSaveProxy`
      handlers (`settings_screen.dart:46-83`).
- [ ] Replace with a **Provider** card: server URL, username, account status and `exp_date` from
      `XtreamUserInfo`, and a "Test connection" button that re-authenticates against the provider.
- [ ] Keep the existing "Active Catalog & Storage Stats", force-resync and clear-cache sections.

### B4 — Series info call

- [ ] `media_details_modal.dart:84-86` — `ref.read(apiClientProvider).getSeriesInfo(sourceId, id)`
      becomes `ref.read(xtreamClientProvider)!.getSeriesInfo(id)`; handle the null-client case.
- [ ] Leave the fake download feedback at `:121-131` alone; **C3 replaces it.**

# Wave C — C1/C4 in batch 4, C2/C3 in batch 5 *(needs A3 + A5 + B2)*

| # | Task | Owns |
|---|---|---|
| C1 | Queue engine | `lib/features/downloads/download_task.dart`, `download_queue_provider.dart`, `download_engine.dart`, `test/features/download_queue_test.dart` |
| C2 | Downloads screen | `lib/features/downloads/presentation/downloads_screen.dart` |
| C3 | Live progress in cards/modal | `lib/features/catalog/presentation/widgets/media_card.dart`, `.../media_details_modal.dart` |
| C4 | Routing + nav | `lib/features/navigation/app_router.dart`, `lib/features/navigation/app_shell.dart` |

- [ ] **C1** — `DownloadQueueNotifier` per contract, backed by `background_downloader` (or the A5
      fallback), persisting through A3's `downloads` table. Completed files move to public storage;
      store the resulting MediaStore URI on the row. Enqueue helpers take the account so they can
      call B2's URL builders.
- [ ] **C2** — Downloads screen listing queued/running/complete/failed with per-item progress,
      pause/resume/cancel/retry, and "open file" via `url_launcher` (already a dependency).
- [ ] **C3** — Replace the fake feedback: `media_card.dart:57-66` flips a bool and resets it on a
      2.5s `Timer`, and `media_details_modal.dart:121-131` does the same. Both bind to
      `downloadTaskProvider`, showing real progress and surfacing failures instead of swallowing them.
      *Sequenced after B4, which owns the same modal file.*
- [ ] **C4** — Register `/downloads` and add it to both navigation surfaces in `app_shell.dart`
      (bottom bar and the ≥800dp rail).

# Wave D — batch 6, strictly serial (one agent at a time)

- [ ] **D1 — Delete the backend.** Remove `lib/core/network/api_client.dart` and
      `lib/core/providers/backend_config_provider.dart`; strip `endpointSources`,
      `endpointDownload`, `endpointXtreamProxy`, `defaultBaseUrl`, `localhostBaseUrl`, `keyBaseUrl`
      from `api_constants.dart` (keep the prefs keys and timeouts); remove the re-export at
      `catalog_provider.dart:15`; delete `test/core/api_client_test.dart`. Gate:
      `grep -rn "10.0.2.2\|api/proxy\|api/sources\|api/download" lib/ test/ integration_test/`
      returns nothing. This is the commit that must restore a clean `flutter analyze`.
- [ ] **D2 — Dart package rename.** `nodecast_catalog_flutter` → the real name in `pubspec.yaml`
      and every `package:` import across `lib/`, `test/`, `integration_test/`. Purely mechanical,
      conflicts with everything, so it runs alone and last.
- [ ] **D3 — Verification** (below).

# Verification

Automated:

- [ ] `flutter analyze` → 0 issues.
- [ ] `flutter test` → all green, including the new Xtream client, DB migration, download URL and
      queue tests.
- [ ] `integration_test/local/real_login_test.dart` — already built for exactly this
      (`--dart-define-from-file=integration_test/local/secrets.properties`, keys
      `xtream_serverUrl` / `xtream_username` / `xtream_password` / `xtream_label`). Update it to
      assert login succeeds **with no backend running**, which is the whole point of this migration.

Manual, on a real Android device with the Node server **stopped**:

- [ ] Fresh install → add an Xtream account → login succeeds; a wrong password shows a clear error
      rather than hanging (the `auth: 0`-with-HTTP-200 case).
- [ ] Full sync completes; movie and series counts match the provider; the UI stays responsive
      throughout (no ANR on the 40k-item parse/insert).
- [ ] Search, category filter and sort respond without visible lag on both Movies and Series.
- [ ] Open a series → seasons and episodes load.
- [ ] Download a movie and an episode → progress advances, the notification updates, pause/resume
      and cancel work, and the files appear in the system Downloads app and play.
- [ ] Background the app mid-download → it continues; kill and relaunch → the task is restorable.
- [ ] Airplane mode → cached catalog still browses; sync reports a clear network error.
- [ ] Upgrade path: install the pre-migration build, then the new one over it — the v1→v2 DB
      migration must not lose the cached catalog.
- [ ] Add a second account, switch between them, confirm catalogs stay separate, then remove one and
      confirm its cached rows are gone.

# Risks

- **`background_downloader` fit** — the largest unknown, which is why A5 validates it in Wave A
  rather than inside Wave C. A no-go reshapes C1 substantially.
- **Provider variance.** Xtream implementations differ in casing, in whether `episodes` is a map or
  a list, and in empty-result shapes. `SeriesDetails.fromJson` (`series_details.dart:83-129`)
  already handles both episode shapes; keep parsing defensive elsewhere.
- **Memory on a 40k catalog.** The whole catalog lives in memory as `List<MediaItem>` in
  `CatalogState`. A1/A3/A4 cut the spikes; if a low-RAM device still struggles, the fallback is
  paging the grid from A3's `searchMedia` instead of from state.
- **Non-compiling window.** The tree does not fully build between Wave B and D1. Waves B and C
  should land close together, and D1 is the gate that restores green.
- **Wave A contract drift.** If A1 needs to deviate from the frozen contract, it must say so before
  batch 3 starts — otherwise three agents build against a signature that no longer exists. The
  batch gates exist precisely so drift is caught at a review point rather than mid-flight.
