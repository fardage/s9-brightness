# Releasing

Updates are delivered with [Sparkle](https://sparkle-project.org). The app reads its feed from
`https://github.com/fardage/s9-brightness/releases/latest/download/appcast.xml`, so **every release
must include an `appcast.xml`**.

The app ships as a DMG rather than a zip: the embedded Sparkle framework relies on symlinks, which
some unarchivers and file-sync tools break, and Gatekeeper then rejects the app.

## Release

From a clean `main` that is in sync with `origin/main`:

```
scripts/release.sh --notes "- **Fixed**: …" 1.3
```

`--notes-file FILE` works too. The notes are the release highlights; the script adds the update
instructions and the DMG's SHA-256 below them, like the earlier releases.

The script bumps `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` (the build number must increase,
so it adds one), archives, exports with Developer ID, notarizes and staples the app, builds,
signs, notarizes and staples the DMG, verifies both, and creates the signed appcast. It then shows
the release notes and asks before it commits "Bump version to 1.3", tags `v1.3`, pushes and creates
the GitHub release. Pass `--yes` to skip the question.

To try everything except publishing, run `scripts/release.sh --dry-run 1.3`. It builds and
notarizes into `build/release/1.3/`, then restores the version in the project.

## Setup

You need:

- The `Developer ID Application: Marvin Tseng (7C48W538SL)` certificate in your login keychain.
- The Sparkle signing key in your login keychain. Restore it from 1Password with
  `generate_keys -f <file>` if needed.
- A `notarytool` keychain profile, here `S9Brightness-notary-api`, using an App Store Connect API key.
- Xcode 27, expected at `/Applications/Xcode_27.1.app`. Set `DEVELOPER_DIR` to use another install.
- `gh`, logged in.

Sparkle's `generate_appcast` is taken from the package artifacts the script's own build resolves
into `build/DerivedData`, so there is nothing to install.
