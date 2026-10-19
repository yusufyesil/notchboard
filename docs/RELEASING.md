# Releasing

How to ship a signed, notarized Notchboard that opens without Gatekeeper warnings, publish it as a GitHub release, and offer it through Homebrew.

None of this is needed to build from source: `./build.sh` signs the app ad hoc, which is enough on the machine that built it.

## 1. One-time setup

1. **Apple Developer Program** membership (paid, yearly).
2. A **Developer ID Application** certificate. Create it in Xcode (Settings › Accounts › Manage Certificates › + › Developer ID Application) or at developer.apple.com, and keep it in your login keychain.
3. An **app-specific password** for notarization (appleid.apple.com › Sign-In and Security › App-Specific Passwords), or an App Store Connect API key.
4. Store the notarization credentials in the keychain once:

   ```bash
   xcrun notarytool store-credentials notchboard \
     --apple-id "<your Apple ID>" --team-id "<TEAMID>" --password "<app-specific password>"
   ```

5. Find your signing identity:

   ```bash
   security find-identity -v -p codesigning
   # "Developer ID Application: Your Name (TEAMID)"
   ```

## 2. Entitlements

A notarized app must use the Hardened Runtime. With it on, sending Apple Events to Claude (what opens a chat in the right profile) needs an entitlement. It is in `Support/Notchboard.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.automation.apple-events</key><true/>
</dict></plist>
```

Notchboard is not sandboxed: it reads Claude Desktop's folders and project folders directly.

## 3. Build, sign, notarize

`scripts/package.sh` builds a universal app and a drag-to-install DMG in `dist/`:

```bash
# Ad hoc signed (no certificate): users approve it once under Privacy & Security
scripts/package.sh 0.3.0

# Developer ID signed, notarized and stapled
IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=notchboard \
  scripts/package.sh 0.3.0
```

It uses `scripts/bundle.sh` (shared with `build.sh`) for the bundle layout and Info.plist, and `Support/Notchboard.entitlements` for the Hardened Runtime. It prints the DMG's SHA-256, which the Homebrew cask needs.

Check a signed build:

```bash
M=$(mktemp -d) && hdiutil attach -nobrowse -mountpoint "$M" dist/Notchboard.dmg
spctl --assess --type execute --verbose "$M/Notchboard.app"   # accepted, source=Notarized Developer ID
hdiutil detach "$M"
```

If notarization fails, read the log: `xcrun notarytool log <submission-id> --keychain-profile notchboard`.

## 4. Release with GitHub Actions

Add these repository secrets (Settings › Secrets and variables › Actions):

| Secret | What |
|---|---|
| `DEVELOPER_ID_P12` | The Developer ID certificate and private key, exported from Keychain Access as `.p12`, then `base64 -i cert.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | The password you set on the `.p12` |
| `SIGNING_IDENTITY` | `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | Notarization credentials |

Then add `.github/workflows/release.yml`. It runs when you push a tag like `v0.3.0`:

```yaml
name: Release
on:
  push:
    tags: ["v*"]
permissions:
  contents: write
jobs:
  release:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Import signing certificate
        env:
          P12: ${{ secrets.DEVELOPER_ID_P12 }}
          P12_PASSWORD: ${{ secrets.DEVELOPER_ID_P12_PASSWORD }}
        run: |
          KEYCHAIN=$RUNNER_TEMP/build.keychain
          echo "$P12" | base64 --decode > $RUNNER_TEMP/cert.p12
          security create-keychain -p "" $KEYCHAIN
          security set-keychain-settings -lut 21600 $KEYCHAIN
          security unlock-keychain -p "" $KEYCHAIN
          security import $RUNNER_TEMP/cert.p12 -k $KEYCHAIN -P "$P12_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: -s -k "" $KEYCHAIN
          security list-keychains -d user -s $KEYCHAIN

      - name: Build, sign, notarize
        env:
          VERSION: ${{ github.ref_name }}
          IDENTITY: ${{ secrets.SIGNING_IDENTITY }}
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          APPLE_APP_PASSWORD: ${{ secrets.APPLE_APP_PASSWORD }}
        run: |
          VERSION=${VERSION#v}
          # In CI, store the notarization credentials in a profile first
          xcrun notarytool store-credentials notchboard \
            --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD"
          NOTARY_PROFILE=notchboard scripts/package.sh "$VERSION"

      - name: Publish release
        env:
          GH_TOKEN: ${{ github.token }}
        run: gh release create "$GITHUB_REF_NAME" dist/Notchboard.dmg --generate-notes
```

Release checklist:

1. Update the tested Claude Desktop and macOS versions in the README.
2. Bump the version (`VERSION` in `build.sh`, and the tag).
3. `git tag v0.3.0 && git push origin v0.3.0`.
4. Download the DMG from the release, open it on another Mac (or a fresh user account) and check that Gatekeeper accepts it.

## 5. Homebrew cask

Start with your own tap; the official `homebrew/cask` repository expects a project with some users and a notarized app.

1. Create a public repository named `homebrew-tap` under the same account.
2. Add `Casks/notchboard.rb`:

   ```ruby
   cask "notchboard" do
     version "0.3.0"
     sha256 "<shasum -a 256 of Notchboard.dmg>"

     url "https://github.com/yusufyesil/notchboard/releases/download/v#{version}/Notchboard.dmg"
     name "Notchboard"
     desc "Claude Desktop chats, routines and profiles in the MacBook notch"
     homepage "https://github.com/yusufyesil/notchboard"

     depends_on macos: ">= :sonoma"

     app "Notchboard.app"

     uninstall launchctl: "app.notchboard",
               quit:      "app.notchboard"

     zap trash: [
       "~/Library/Application Support/Notchboard",
       "~/Library/LaunchAgents/app.notchboard.plist",
       "~/Library/Preferences/app.notchboard.plist",
     ]
   end
   ```

3. Check it: `brew audit --cask --new yusufyesil/tap/notchboard` and `brew install --cask yusufyesil/tap/notchboard`.
4. Users install with:

   ```bash
   brew install --cask yusufyesil/tap/notchboard
   ```

5. On each release, update `version` and `sha256`. The workflow can do this too: add a step that runs `brew bump-cask-pr` or commits to the tap with a token that has access to it.

## Notes for distributed builds

- `build.sh` installs to `~/Applications`; a cask installs to `/Applications`. The login item writes the path of the running executable, so both work.
- A future version could replace the LaunchAgent with `SMAppService.mainApp`, which shows Notchboard under Login Items in System Settings.
