# Releasing

The same sandboxed build ships two ways: as a DMG on GitHub Releases and on the Mac App Store.

The DMG build finds out about new versions itself. Once a day it reads the latest release from the
GitHub API, and if its tag is newer than the running version, the gear menu offers **Download
Version …**, which opens the release page. App Store installs (recognized by Apple's App Store
signature) never check, since the App Store updates them.

## DMG release

From a clean `main` that is in sync with `origin/main`:

```
scripts/release.sh --notes "- **Fixed**: …" 1.3
```

`--notes-file FILE` works too. The notes are the release highlights; the script adds the install
instructions and the DMG's SHA-256 below them, like the earlier releases.

The script bumps `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` (the build number must increase,
so it adds one), archives, exports with Developer ID, notarizes and staples the app, builds,
signs, notarizes and staples the DMG, and verifies both. It then shows the release notes and asks
before it commits "Bump version to 1.3", tags `v1.3`, pushes and creates the GitHub release. Pass
`--yes` to skip the question. The tag must be `v` plus the version, since the update check
compares it with the app's version.

To try everything except publishing, run `scripts/release.sh --dry-run 1.3`. It builds and
notarizes into `build/release/1.3/`, then restores the version in the project.

## App Store release

Upload the archive `release.sh` made for the DMG, so both channels ship the same build:

```
xcodebuild -exportArchive -archivePath build/release/1.3/S9Brightness.xcarchive \
  -exportPath build/release/1.3/appstore -exportOptionsPlist scripts/ExportOptions-AppStore.plist \
  -allowProvisioningUpdates
```

`ExportOptions-AppStore.plist` re-signs the app for the App Store and uploads it straight to App
Store Connect.

## Setup

You need:

- The `Developer ID Application: Marvin Tseng (7C48W538SL)` certificate in your login keychain for
  the DMG, and an Apple Distribution certificate for the App Store (Xcode creates it with
  `-allowProvisioningUpdates` when your account is signed in).
- A `notarytool` keychain profile, here `S9Brightness-notary-api`, using an App Store Connect API key.
- Xcode 27, expected at `/Applications/Xcode_27.1.app`. Set `DEVELOPER_DIR` to use another install.
- `gh`, logged in.
