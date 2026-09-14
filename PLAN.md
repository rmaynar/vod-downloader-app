# Nodecast Catalog Flutter - Implementation Plan

## Overview
A Flutter mirror of the `nodecast-catalog` React application. The primary target is a fully functional Android version. The Flutter app will communicate with the existing Node.js proxy backend (expected at `http://10.0.2.2:3000` for the Android emulator). 
*Note: The "Static Website Export" feature is intentionally excluded from this implementation.*

## 1. Project Setup and Architecture
- [x] Initialize Flutter project (`nodecast_catalog_flutter`).
- [x] Define folder structure (`lib/core`, `lib/features`).
- [x] Add dependencies: `flutter_riverpod` (state management), `dio` (HTTP client), `sqflite` (local database replacing Dexie), `path_provider` (file paths), `go_router` (navigation), `cached_network_image` (efficient image loading).
- [x] Configure the app's Dark Theme to match the original React application's aesthetics.

## 2. Core Services (Data Layer)
- [x] **API Client (`lib/core/network/api_client.dart`)**: Dio client handling requests to `/api/sources`, `/api/proxy/xtream/*`, etc.
- [x] **Local Database (`lib/core/database/database_service.dart`)**: `sqflite` with tables mirroring the IndexedDB schema (`movies`, `series`, `vodCategories`, `seriesCategories`, `sources`, `meta`).
- [x] **Repositories**: Sync/caching logic lives in `CatalogNotifier` (`lib/features/catalog/providers/catalog_provider.dart`), coordinating API fetches with SQLite caching.

## 3. State Management (Domain Layer)
- [x] **Catalog State (`lib/features/catalog/providers/catalog_provider.dart`)**: Riverpod `StateNotifierProvider` managing current account/source, movies, series, categories.
- [x] **Auth State**: `CatalogState.isAuthenticated` / `currentSourceId` drives `go_router` redirects between `/login` and the app shell.
- [x] **Sync State**: `isSyncing` / `syncProgress` fields with UI feedback (pulsing header pill, spinning sync icon).

## 4. UI: Authentication & Setup
- [x] **Login Page** (`lib/features/auth/presentation/login_screen.dart`): full Xtream source add/select flow.

## 5. UI: Navigation & Layout
- [x] **Routing**: `go_router` set up in `lib/features/navigation/app_router.dart` with `/login`, `/`, `/movies`, `/series`, `/settings`, auth-gated via redirect.
- [x] **App Layout** (`lib/features/navigation/app_shell.dart`): top bar + BottomNavigationBar on phones, NavigationRail on wide screens (≥800dp).

## 6. UI: Catalog & Browsing
- [x] **Catalog Grid** (`lib/features/catalog/presentation/widgets/catalog_grid.dart`): `GridView.builder` with batched infinite scroll (loads more 400px before the end).
- [x] **Media Card** (`.../widgets/media_card.dart`): poster, rating badge, title.
- [x] **Search & Filters**: in-memory title search + category filter + sort, implemented per-screen in `movies_screen.dart` / `series_screen.dart` against the cached SQLite-backed state.

## 7. UI: Media Details & Downloading
- [x] **Media Details Modal** (`.../widgets/media_details_modal.dart`): synopsis, rating, release year; seasons/episodes list with per-episode download for series.
- [x] **Download Functionality** (`lib/core/services/download_service.dart`): Dio-based download to app-scoped external storage, used by both movies and series episodes; covered by unit tests.

## 8. UI: Settings
- [x] **Settings Page** (`lib/features/settings/presentation/settings_screen.dart`): backend proxy config + "Active Catalog & Storage Stats".
- [x] **Sync Button**: header quick-sync icon and Home screen's "Force Re-sync Catalog" button both call `syncCatalog(forceSync: true)`.
- [ ] *(Static Website Export UI and logic are omitted as requested)*

## Status notes (2026-09-14)
All checklist items above are implemented and were smoke-tested on a live Android emulator against real backend data (40k+ movies / 11k+ series). During this pass the following bugs were found and fixed, each backed by a regression test in `test/`:
- `home_screen.dart` called `syncCatalog(null, forceSync: true)` with a stray positional argument against a named-parameter-only method — this broke the build entirely (`flutter test` / `flutter run` both failed to compile).
- Three duplicate/dead scaffolding files from an earlier refactor (`core/routing/app_router.dart`, `core/services/api_client.dart`, and two 1-line provider re-export stubs) were removed; all real imports now point directly at the active implementations.
- The app header ("VOD Downloader" wordmark) overflowed by 34px on phone-width screens; now hidden below the tablet breakpoint, matching the existing nav-links pattern.
- `_buildStatCard`'s inner `Row` (Home screen stat cards) had no `Expanded`/ellipsis around its text column, overflowing at ~720-820dp widths; fixed to match the working "Active Source" card pattern.

`flutter analyze` is clean (0 issues) and `flutter test` passes (19/19), including two new widget-level regression tests guarding the overflow and sync-call-signature bugs above.
