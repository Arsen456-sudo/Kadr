#!/usr/bin/env bash
set -euo pipefail
umask 077

for name in IOS_DISTRIBUTION_P12_BASE64 IOS_DISTRIBUTION_P12_PASSWORD IOS_AD_HOC_PROFILE_BASE64 IOS_IPA_PASSPHRASE; do
    if [[ -z "${!name:-}" ]]; then
        echo "::error::Missing GitHub environment secret: $name."
        exit 1
    fi
done
if [[ "${#IOS_IPA_PASSPHRASE}" -lt 24 || "$IOS_IPA_PASSPHRASE" == *$'\n'* || "$IOS_IPA_PASSPHRASE" == *$'\r'* ]]; then
    echo "::error::Use a single-line IPA passphrase of at least 24 characters."
    exit 1
fi

work_dir="$(mktemp -d "${RUNNER_TEMP:?}/kadr-ipa.XXXXXXXX")"
keychain="$work_dir/signing.keychain-db"
installed_profile=""
previous_keychains=()
while IFS= read -r line; do
    previous_keychains+=("$line")
done < <(security list-keychains -d user | sed -E 's/^[[:space:]]*"(.+)"$/\1/')

cleanup() {
    security delete-keychain "$keychain" >/dev/null 2>&1 || true
    if [[ -n "${previous_keychains[0]:-}" ]]; then
        security list-keychains -d user -s "${previous_keychains[@]}" >/dev/null 2>&1 || true
    fi
    if [[ -n "$installed_profile" ]]; then
        rm -f -- "$installed_profile"
    fi
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

printf '%s' "$IOS_DISTRIBUTION_P12_BASE64" | base64 -D > "$work_dir/distribution.p12"
printf '%s' "$IOS_AD_HOC_PROFILE_BASE64" | base64 -D > "$work_dir/adhoc.mobileprovision"
unset IOS_DISTRIBUTION_P12_BASE64 IOS_AD_HOC_PROFILE_BASE64
security cms -D -i "$work_dir/adhoc.mobileprovision" > "$work_dir/profile.plist"

keychain_password="$(openssl rand -hex 32)"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$work_dir/distribution.p12" -f pkcs12 -k "$keychain" \
    -P "$IOS_DISTRIBUTION_P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
unset IOS_DISTRIBUTION_P12_PASSWORD
rm -f -- "$work_dir/distribution.p12"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
unset keychain_password
security list-keychains -d user -s "$keychain"
security find-identity -v -p codesigning "$keychain" |
    awk '/"Apple Distribution:/ { print $2 }' > "$work_dir/certificate-fingerprints.txt"

python3 - "$work_dir" <<'PY'
import datetime
import hashlib
import pathlib
import plistlib
import re
import sys
import uuid

work = pathlib.Path(sys.argv[1])
profile = plistlib.loads((work / "profile.plist").read_bytes())
entitlements = profile.get("Entitlements", {})
if (
    "iOS" not in profile.get("Platform", [])
    or not profile.get("ProvisionedDevices")
    or profile.get("ProvisionsAllDevices")
    or entitlements.get("get-task-allow")
):
    sys.exit("::error::Use an iOS Ad Hoc distribution profile with registered devices.")
if profile["ExpirationDate"].replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc):
    sys.exit("::error::The Ad Hoc provisioning profile has expired.")

prefix, _, bundle_id = entitlements.get("application-identifier", "").partition(".")
teams = profile.get("TeamIdentifier", [])
if (
    prefix not in profile.get("ApplicationIdentifierPrefix", [])
    or not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle_id)
    or len(teams) != 1
    or not re.fullmatch(r"[A-Z0-9]{10}", teams[0])
):
    sys.exit("::error::The profile must contain an explicit iOS App ID and a valid team.")

allowed = {hashlib.sha1(cert).hexdigest().upper() for cert in profile.get("DeveloperCertificates", [])}
identities = set((work / "certificate-fingerprints.txt").read_text().upper().split())
matching = allowed & identities
if len(matching) != 1:
    sys.exit("::error::The .p12 must contain a valid Apple Distribution identity from the Ad Hoc profile.")
fingerprint = matching.pop()
profile_id = profile["UUID"]
uuid.UUID(profile_id)
if not re.fullmatch(r"[A-Fa-f0-9-]{36}", profile_id):
    sys.exit("::error::Invalid provisioning profile identifier.")

(work / "signing.txt").write_text("\n".join([bundle_id, teams[0], profile_id, fingerprint]) + "\n")
(work / "ExportOptions.plist").write_bytes(plistlib.dumps({
    "destination": "export",
    "method": "release-testing",
    "signingStyle": "manual",
    "signingCertificate": fingerprint,
    "teamID": teams[0],
    "provisioningProfiles": {bundle_id: profile_id},
}))
PY

{
    read -r bundle_id
    read -r team
    read -r profile_id
    read -r identity
} < "$work_dir/signing.txt"

profiles_dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$profiles_dir"
profile_target="$profiles_dir/$profile_id.mobileprovision"
if [[ ! -e "$profile_target" ]]; then
    installed_profile="$profile_target"
    cp "$work_dir/adhoc.mobileprovision" "$installed_profile"
fi

xcodebuild -project ios/Kadr.xcodeproj -scheme Kadr -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$work_dir/Kadr.xcarchive" \
    "PRODUCT_BUNDLE_IDENTIFIER=$bundle_id" "DEVELOPMENT_TEAM=$team" \
    "CODE_SIGN_STYLE=Manual" "CODE_SIGN_IDENTITY=$identity" \
    "PROVISIONING_PROFILE=$profile_id" "CURRENT_PROJECT_VERSION=${GITHUB_RUN_NUMBER:?}" archive

xcodebuild -exportArchive -archivePath "$work_dir/Kadr.xcarchive" \
    -exportPath "$work_dir/export" -exportOptionsPlist "$work_dir/ExportOptions.plist"

ipas=("$work_dir/export/"*.ipa)
if [[ "${#ipas[@]}" -ne 1 || ! -s "${ipas[0]}" ]]; then
    echo "::error::Xcode did not export exactly one IPA."
    exit 1
fi
unzip -q "${ipas[0]}" -d "$work_dir/verification"
app="$work_dir/verification/Payload/Kadr.app"
test -s "$app/bunny.mp4"
test -s "$app/sintel.mp4"
test -s "$app/embedded.mobileprovision"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")" = "$bundle_id"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$app/Info.plist")" = iPhoneOS
codesign --verify --deep --strict "$app"

# The Ad Hoc profile contains registered device identifiers. Keep the raw IPA off public Actions artifacts.
output_dir="ios/build/ipa"
mkdir -p "$output_dir"
printf '%s\n' "$IOS_IPA_PASSPHRASE" |
    gpg --batch --yes --pinentry-mode loopback --no-symkey-cache --passphrase-fd 0 \
        --symmetric --cipher-algo AES256 --s2k-digest-algo SHA512 \
        --output "$output_dir/Kadr.ipa.gpg" "${ipas[0]}"
test -s "$output_dir/Kadr.ipa.gpg"
