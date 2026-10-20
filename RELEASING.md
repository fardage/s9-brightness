# Releasing

Updates are delivered with [Sparkle](https://sparkle-project.org). The app reads its feed from
`https://github.com/fardage/s9-brightness/releases/latest/download/appcast.xml`, so **every release
must include an `appcast.xml`**.

You need the Sparkle signing key in your login keychain (restore it from 1Password with
`generate_keys -f <file>` if needed) and a `notarytool` keychain profile (here `S9Brightness-notary-api`, using an App Store Connect API key).
Sparkle's tools are in
`~/Library/Developer/Xcode/DerivedData/S9Brightness-*/SourcePackages/artifacts/sparkle/Sparkle/bin/`
after building the project in Xcode.

The app ships as a DMG rather than a zip: the embedded Sparkle framework relies on symlinks, which
some unarchivers and file-sync tools break, and Gatekeeper then rejects the app.

1. Bump `MARKETING_VERSION` (e.g. `1.1`) and `CURRENT_PROJECT_VERSION` (must increase) in the project.
2. In Xcode: **Product › Archive**, then **Distribute App › Direct Distribution**. This signs with
   Developer ID, notarizes and staples. Export the app.
3. Build, sign, notarize and staple the DMG in an empty `release` folder:
   ```
   mkdir -p dmg release && ditto S9Brightness.app dmg/S9Brightness.app && ln -s /Applications dmg/Applications
   hdiutil create -volname "S9 Brightness" -srcfolder dmg -format UDZO -fs APFS release/S9Brightness-1.1.dmg
   codesign --sign "Developer ID Application: Marvin Tseng (7C48W538SL)" --timestamp release/S9Brightness-1.1.dmg
   xcrun notarytool submit release/S9Brightness-1.1.dmg --keychain-profile S9Brightness-notary-api --wait
   xcrun stapler staple release/S9Brightness-1.1.dmg
   ```
4. Create the signed appcast:
   ```
   generate_appcast --download-url-prefix https://github.com/fardage/s9-brightness/releases/download/v1.1/ release
   ```
5. Publish both files:
   ```
   gh release create v1.1 release/S9Brightness-1.1.dmg release/appcast.xml --title "S9 Brightness 1.1" --notes "…"
   ```
