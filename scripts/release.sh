#!/bin/bash
# Builds, signs, notarizes and publishes a release. See RELEASING.md.
#
#   scripts/release.sh [--dry-run] [--yes] (--notes TEXT | --notes-file FILE) VERSION
#
# --dry-run builds everything up to the appcast, then restores the version bump. It does not
# commit, push or publish, and it skips the checks against the remote.
set -euo pipefail

REPO=fardage/s9-brightness
IDENTITY="Developer ID Application: Marvin Tseng (7C48W538SL)"
NOTARY_PROFILE=S9Brightness-notary-api

# The project uses Xcode 27's JSON project format.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode_27.1.app/Contents/Developer}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XCODEPROJ="$ROOT/S9Brightness/S9Brightness.xcodeproj"
PROJECT_FILE="$XCODEPROJ/project.xcproj"
DERIVED_DATA="$ROOT/build/DerivedData"
SPARKLE_BIN="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin"

dry_run=0 assume_yes=0 notes="" notes_file="" version=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --yes) assume_yes=1 ;;
    --notes) notes="${2:?--notes needs text}"; shift ;;
    --notes-file) notes_file="${2:?--notes-file needs a path}"; shift ;;
    -*) echo "Unknown option $1" >&2; exit 2 ;;
    *) version="$1" ;;
  esac
  shift
done

die() { echo "error: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

[[ "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || die "pass a version like 1.3 or 1.3.1"
if [[ -n "$notes_file" ]]; then notes="$(cat "$notes_file")"; fi
[[ $dry_run -eq 1 || -n "$notes" ]] || die "pass --notes or --notes-file (the release highlights)"

tag="v$version"
work="$ROOT/build/release/$version"
out="$work/release"   # generate_appcast reads every archive in this folder, so it holds only the DMG
dmg="$out/S9Brightness-$version.dmg"
bumped=0 committed=0

# Runs a command with its output going to a log, which is shown only if the command fails.
logged() {
  local name="$1"; shift
  "$@" >"$work/$name.log" 2>&1 || { tail -n 40 "$work/$name.log" >&2; die "$name failed (full log: $work/$name.log)"; }
}

notarize() {
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait >"$work/notarize.log" 2>&1 || true
  grep -q "status: Accepted" "$work/notarize.log" || { cat "$work/notarize.log" >&2; die "notarization of $(basename "$1") was not accepted"; }
}

# Replaces the value of a build setting that appears exactly once in the project file.
set_build_setting() {
  local key="$1" value="$2"
  [[ "$(grep -cE "^[[:space:]]*\"$key\": \"[^\"]*\",$" "$PROJECT_FILE")" == 1 ]] || die "expected exactly one $key in the project"
  KEY="$key" VALUE="$value" perl -pi -e 's/^([[:space:]]*"\Q$ENV{KEY}\E": ")[^"]*(")/$1$ENV{VALUE}$2/' "$PROJECT_FILE"
}

get_build_setting() {
  sed -nE "s/^[[:space:]]*\"$1\": \"([^\"]*)\",$/\1/p" "$PROJECT_FILE"
}

restore_project() {
  if [[ $bumped -eq 1 && $committed -eq 0 ]]; then
    git -C "$ROOT" checkout -- "$PROJECT_FILE"
    echo "Restored the version in the project."
  fi
}
trap restore_project EXIT

step "Checking prerequisites"
cd "$ROOT"
security find-identity -v -p codesigning | grep -qF "$IDENTITY" || die "signing identity '$IDENTITY' not found"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || die "notarytool keychain profile $NOTARY_PROFILE not usable"
if [[ $dry_run -eq 1 ]]; then
  git diff --quiet -- "$PROJECT_FILE" || die "the project file has uncommitted changes"
else
  [[ "$(git rev-parse --abbrev-ref HEAD)" == main ]] || die "release from main"
  [[ -z "$(git status --porcelain)" ]] || die "the working tree is not clean"
  git fetch --quiet origin main --tags
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die "main is not in sync with origin/main"
  ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "tag $tag already exists"
  [[ -z "$(git ls-remote --tags origin "refs/tags/$tag")" ]] || die "tag $tag already exists on origin"
  gh auth status >/dev/null 2>&1 || die "gh is not logged in"
fi

current_version="$(get_build_setting MARKETING_VERSION)"
current_build="$(get_build_setting CURRENT_PROJECT_VERSION)"
build=$((current_build + 1))
if [[ $dry_run -eq 0 ]]; then
  [[ "$(printf '%s\n%s\n' "$current_version" "$version" | sort -V | tail -n1)" == "$version" && "$current_version" != "$version" ]] \
    || die "$version is not newer than the current version $current_version"
fi

rm -rf "$work"
mkdir -p "$work" "$out"

step "Setting version $version (build $build)"
set_build_setting MARKETING_VERSION "$version"
set_build_setting CURRENT_PROJECT_VERSION "$build"
bumped=1
settings="$(xcodebuild -showBuildSettings -project "$XCODEPROJ" -scheme S9Brightness -configuration Release 2>/dev/null)"
grep -qE "^[[:space:]]*MARKETING_VERSION = $version$" <<<"$settings" || die "Xcode does not see MARKETING_VERSION $version"
grep -qE "^[[:space:]]*CURRENT_PROJECT_VERSION = $build$" <<<"$settings" || die "Xcode does not see CURRENT_PROJECT_VERSION $build"

step "Archiving"
logged archive xcodebuild archive -project "$XCODEPROJ" -scheme S9Brightness -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$work/S9Brightness.xcarchive" \
  -derivedDataPath "$DERIVED_DATA" -allowProvisioningUpdates

step "Exporting with Developer ID"
logged export xcodebuild -exportArchive -archivePath "$work/S9Brightness.xcarchive" \
  -exportPath "$work/export" -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist" -allowProvisioningUpdates
app="$work/export/S9Brightness.app"

for pair in "CFBundleShortVersionString:$version" "CFBundleVersion:$build"; do
  actual="$(/usr/libexec/PlistBuddy -c "Print :${pair%%:*}" "$app/Contents/Info.plist")"
  [[ "$actual" == "${pair#*:}" ]] || die "exported app has ${pair%%:*} $actual, expected ${pair#*:}"
done

step "Notarizing the app"
ditto -c -k --keepParent "$app" "$work/S9Brightness.zip"
notarize "$work/S9Brightness.zip"
logged staple-app xcrun stapler staple "$app"

step "Building, signing and notarizing the DMG"
mkdir -p "$work/dmg"
ditto "$app" "$work/dmg/S9Brightness.app"
ln -s /Applications "$work/dmg/Applications"
logged hdiutil hdiutil create -volname "S9 Brightness" -srcfolder "$work/dmg" -format UDZO -fs APFS "$dmg"
logged codesign-dmg codesign --sign "$IDENTITY" --timestamp "$dmg"
notarize "$dmg"
logged staple-dmg xcrun stapler staple "$dmg"

step "Verifying"
logged verify-codesign codesign --verify --deep --strict "$app"
logged verify-spctl-app spctl -a -t exec -vv "$app"
logged verify-spctl-dmg spctl -a -t open --context context:primary-signature -v "$dmg"
logged validate-app xcrun stapler validate "$app"
logged validate-dmg xcrun stapler validate "$dmg"

step "Creating the appcast"
[[ -x "$SPARKLE_BIN/generate_appcast" ]] || die "generate_appcast not found in $SPARKLE_BIN"
logged appcast "$SPARKLE_BIN/generate_appcast" --download-url-prefix "https://github.com/$REPO/releases/download/$tag/" "$out"
appcast="$out/appcast.xml"
grep -q "<sparkle:version>$build</sparkle:version>" "$appcast" || die "appcast has the wrong build number"
grep -q "<sparkle:shortVersionString>$version</sparkle:shortVersionString>" "$appcast" || die "appcast has the wrong version"
grep -qF "url=\"https://github.com/$REPO/releases/download/$tag/S9Brightness-$version.dmg\"" "$appcast" || die "appcast has the wrong download URL"
grep -q "sparkle:edSignature=" "$appcast" || die "appcast is not signed"

sha="$(shasum -a 256 "$dmg" | cut -d' ' -f1)"

if [[ $dry_run -eq 1 ]]; then
  step "Dry run done"
  echo "DMG:     $dmg"
  echo "Appcast: $appcast"
  echo "SHA-256: $sha"
  exit 0
fi

body="$notes

Update with **Check for Updates…** in the gear menu, or open the DMG and drag S9 Brightness to Applications. Signed with Developer ID and notarized by Apple. Requires macOS 14 or later.

SHA-256: \`$sha\`"

step "Ready to publish S9 Brightness $version (build $build)"
echo "$body"
echo
if [[ $assume_yes -eq 0 ]]; then
  read -r -p "Commit, tag, push and publish? Users get the update right away. [y/N] " answer
  [[ "$answer" == y || "$answer" == Y ]] || die "aborted"
fi

step "Publishing"
git commit --quiet -m "Bump version to $version" -- "$PROJECT_FILE"
committed=1
git tag "$tag"
git push origin main "$tag"
gh release create "$tag" "$dmg" "$appcast" --repo "$REPO" --verify-tag --title "S9 Brightness $version" --notes "$body" \
  || die "the release was not created, but $tag is pushed. Retry with: gh release create $tag $dmg $appcast --repo $REPO --verify-tag"

echo "Published https://github.com/$REPO/releases/tag/$tag"
