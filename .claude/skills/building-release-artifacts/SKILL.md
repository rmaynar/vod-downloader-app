---
name: building-release-artifacts
description: Use when building a distributable Android APK or macOS DMG for the VOD Downloader app, or preparing artifacts for a tagged release.
---

# Building Release Artifacts

## Overview

Builds this Flutter app's release binaries for Android and macOS and stages them under
`dist/` as `vod-downloader-<version>.apk` / `.dmg`, ready to attach to a GitHub release.

## Before you start

- Read `version:` in `pubspec.yaml` (`X.Y.Z+N`). Filenames use `X.Y.Z` only — the `+N` is
  Android's internal `versionCode`.
- Check whether `X.Y.Z` was already released — `gh release view vX.Y.Z` (404 means it
  wasn't). If it was, bump `+N` before building, even though `X.Y.Z` stays the same: Play
  requires `versionCode` to strictly increase, and it keeps two builds of "the same
  version" distinguishable. If nothing was released yet under this `X.Y.Z`, leave `+N` as
  is — don't bump speculatively, and don't edit `pubspec.yaml` at all unless a bump is
  actually needed.
- Run `flutter pub get` if `pubspec.yaml` or `pubspec.lock` changed since the last build.

## Android APK

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

Check `ls android/key.properties` before claiming anything about signing:
- **Present** (gitignored, per-machine, copied from `key.properties.template`) → real
  release signing.
- **Absent** → the build **silently falls back to the debug key**. It still succeeds and
  installs fine, but the APK cannot be installed as an update over a differently-signed
  build and cannot be uploaded to Play. State which case applies in your summary — don't
  assume or claim "release-signed" without checking.

## macOS DMG

```bash
flutter build macos --release
```

Output app bundle: `build/macos/Build/Products/Release/<PRODUCT_NAME>.app`, where
`<PRODUCT_NAME>` is read from `macos/Runner/Configs/AppInfo.xcconfig` (currently
`VOD Downloader`).

The app is **ad-hoc signed only** — `CODE_SIGN_IDENTITY = "-"` in the Xcode project, no
team, not notarized. Confirm with `codesign -dv "<app>.app"` if unsure (look for
`flags=0x2(adhoc)` and `TeamIdentifier=not set`). This means Gatekeeper will refuse to
open a copy downloaded from the internet ("... is damaged and can't be opened") until the
quarantine flag is cleared:

```bash
xattr -cr "/Applications/VOD Downloader.app"
```

Always mention this caveat and workaround wherever the DMG is distributed (e.g. release
notes) — it is not optional context, it's the difference between the app opening or not
for anyone who downloads it.

Package the `.app` into a DMG with the standard drag-to-Applications layout:

```bash
STAGE=$(mktemp -d)
cp -R "build/macos/Build/Products/Release/VOD Downloader.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "VOD Downloader" -srcfolder "$STAGE" -ov -format UDZO \
  "dist/vod-downloader-<version>.dmg"
rm -rf "$STAGE"
```

## Staging and naming

Both artifacts go in `dist/` at the repo root (gitignored — build output, not source):

```bash
mkdir -p dist
cp build/app/outputs/flutter-apk/app-release.apk "dist/vod-downloader-<version>.apk"
```

## Verify before handing off

- `ls -la dist/` — confirm both files exist and aren't suspiciously small (a broken build
  can still exit 0 with a near-empty artifact).
- `flutter analyze` and `flutter test` clean beforehand — don't stage a build on top of a
  known regression.
- State plainly in your summary: which version was built, the Android signing status
  (debug-fallback vs. real), and the macOS Gatekeeper caveat above.

## Publishing

This skill only builds and stages artifacts — it doesn't publish them. To cut a tagged
release: `git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z`, then
`gh release create vX.Y.Z dist/vod-downloader-<version>.apk dist/vod-downloader-<version>.dmg
--notes-file <file>`. Check prior releases (`gh release view <tag>`) for this repo's notes
format before writing new ones.
