#!/bin/bash
# Archive + export Prep Station for App Store Connect (local Xcode, automatic signing).
# Usage: scripts/archive-ios.sh   (needs the ASC API key in ~/.appstoreconnect/private_keys)
set -euo pipefail
cd "$(dirname "$0")/.."
KEY_ID="${ASC_KEY_ID:-FJ5J86Z82T}"
ISSUER="${ASC_ISSUER_ID:-ddc4a87a-3813-4e5a-aeab-e2e3485cb2a4}"
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER")
xcodegen generate
rm -rf build/PrepStation.xcarchive build/export
xcodebuild archive -project PrepStation.xcodeproj -scheme PrepStation -configuration Release \
  -destination generic/platform=iOS -archivePath build/PrepStation.xcarchive -derivedDataPath build/DD \
  "${AUTH[@]}" DEVELOPMENT_TEAM=5DTN44ACL8 CODE_SIGN_STYLE=Automatic COMPILER_INDEX_STORE_ENABLE=NO
cat > build/ExportOptions.plist <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>destination</key><string>export</string>
<key>method</key><string>app-store-connect</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>5DTN44ACL8</string>
<key>manageAppVersionAndBuildNumber</key><false/>
<key>stripSwiftSymbols</key><true/>
<key>uploadSymbols</key><true/>
</dict></plist>
PL
# Note: no -derivedDataPath on -exportArchive (that flag breaks export).
xcodebuild -exportArchive -archivePath build/PrepStation.xcarchive -exportPath build/export \
  -exportOptionsPlist build/ExportOptions.plist "${AUTH[@]}"
ls -la build/export
