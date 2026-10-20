# Releasing

Updates are delivered with [Sparkle](https://sparkle-project.org). The app reads its feed from
`https://github.com/fardage/s9-brightness/releases/latest/download/appcast.xml`, so **every release
must include an `appcast.xml`**.

You need the Sparkle signing key in your login keychain (restore it from 1Password with
`generate_keys -f <file>` if needed). Sparkle's tools are in
`~/Library/Developer/Xcode/DerivedData/S9Brightness-*/SourcePackages/artifacts/sparkle/Sparkle/bin/`
after building the project in Xcode.

1. Bump `MARKETING_VERSION` (e.g. `1.1`) and `CURRENT_PROJECT_VERSION` (must increase) in the project.
2. In Xcode: **Product › Archive**, then **Distribute App › Direct Distribution**. This signs with
   Developer ID, notarizes and staples. Export the app.
3. Zip it into an empty folder:
   ```
   mkdir release && ditto -c -k --keepParent S9Brightness.app release/S9Brightness-1.1.zip
   ```
4. Create the signed appcast:
   ```
   generate_appcast --download-url-prefix https://github.com/fardage/s9-brightness/releases/download/v1.1/ release
   ```
5. Publish both files:
   ```
   gh release create v1.1 release/S9Brightness-1.1.zip release/appcast.xml --title "S9 Brightness 1.1" --notes "…"
   ```
