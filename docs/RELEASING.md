# Releasing Glance

Glance publishes signed, notarized universal macOS installers from a version tag. The release workflow runs tests, imports temporary signing credentials, builds DMG and PKG installers, submits both to Apple, verifies Gatekeeper acceptance, and creates a GitHub Release with checksums.

## One-time GitHub setup

Create a protected GitHub environment named `release`. Require approval for deployments if the repository plan supports it, and store the following secrets in that environment:

- `DEVELOPER_ID_APPLICATION_P12_BASE64`
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`
- `DEVELOPER_ID_INSTALLER_P12_BASE64`
- `DEVELOPER_ID_INSTALLER_P12_PASSWORD`
- `APP_STORE_CONNECT_KEY_BASE64`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `SPARKLE_EDDSA_PRIVATE_KEY`

Create a private temporary directory outside the repository and open it in Finder:

```sh
credential_export_dir="$(mktemp -d -t glance-signing)"
chmod 700 "$credential_export_dir"
open "$credential_export_dir"
```

From Keychain Access, export the Developer ID Application identity and Developer ID Installer identity, including each private key, into that folder as `DeveloperIDApplication.p12` and `DeveloperIDInstaller.p12`. Protect each export with a different strong password. Encode the files and send the encoded values directly to GitHub Secrets:

```sh
base64 -i "$credential_export_dir/DeveloperIDApplication.p12" \
  -o "$credential_export_dir/DeveloperIDApplication.p12.base64"
gh secret set DEVELOPER_ID_APPLICATION_P12_BASE64 --env release \
  < "$credential_export_dir/DeveloperIDApplication.p12.base64"
gh secret set DEVELOPER_ID_APPLICATION_P12_PASSWORD --env release

base64 -i "$credential_export_dir/DeveloperIDInstaller.p12" \
  -o "$credential_export_dir/DeveloperIDInstaller.p12.base64"
gh secret set DEVELOPER_ID_INSTALLER_P12_BASE64 --env release \
  < "$credential_export_dir/DeveloperIDInstaller.p12.base64"
gh secret set DEVELOPER_ID_INSTALLER_P12_PASSWORD --env release
```

Create a team App Store Connect API key with the minimum role that can submit software for notarization. Download its `.p8` file once and move it into the temporary directory as `AuthKey_KEY_ID.p8`, replacing `KEY_ID` with the key’s identifier. Then store it and its identifiers:

```sh
base64 -i "$credential_export_dir/AuthKey_KEY_ID.p8" \
  -o "$credential_export_dir/AuthKey_KEY_ID.p8.base64"
gh secret set APP_STORE_CONNECT_KEY_BASE64 --env release \
  < "$credential_export_dir/AuthKey_KEY_ID.p8.base64"
gh secret set APP_STORE_CONNECT_KEY_ID --env release
gh secret set APP_STORE_CONNECT_ISSUER_ID --env release
```

After confirming the workflow can sign a release, delete the four certificate files and both API-key files, remove the temporary directory, and clear its shell variable:

```sh
rm -f \
  "$credential_export_dir/DeveloperIDApplication.p12" \
  "$credential_export_dir/DeveloperIDApplication.p12.base64" \
  "$credential_export_dir/DeveloperIDInstaller.p12" \
  "$credential_export_dir/DeveloperIDInstaller.p12.base64" \
  "$credential_export_dir/AuthKey_KEY_ID.p8" \
  "$credential_export_dir/AuthKey_KEY_ID.p8.base64"
rmdir "$credential_export_dir"
unset credential_export_dir
```

Base64 is encoding, not encryption; GitHub Secrets provides storage protection.

Generate the Sparkle EdDSA key once with the version of `generate_keys` resolved by Swift Package Manager. The private key remains in the login Keychain under the account `app.glance.Glance`; add its exported value to the `release` environment:

```sh
swift package resolve
sparkle_tools=".build/artifacts/sparkle/Sparkle/bin"
"$sparkle_tools/generate_keys" --account app.glance.Glance
private_key_file="$(mktemp -u -t glance-sparkle-key)"
"$sparkle_tools/generate_keys" --account app.glance.Glance -x "$private_key_file"
chmod 600 "$private_key_file"
gh secret set SPARKLE_EDDSA_PRIVATE_KEY --env release < "$private_key_file"
unlink "$private_key_file"
unset private_key_file sparkle_tools
```

The command prints the public key that belongs in `SUPublicEDKey` in `support/Info.plist`. Keep an encrypted backup of the private key outside the repository. Losing both the Keychain item and the backup prevents signing future automatic updates with this key.

In the repository release settings, enable immutable releases when available. This locks a published tag and its assets and adds a release attestation.

## Publish a release

1. Update `CFBundleShortVersionString` and increment the integer `CFBundleVersion` in `support/Info.plist`.
2. Merge the change after its required pull-request CI passes.
3. Create and push an annotated tag matching the short version exactly:

```sh
release_version="$(plutil -extract CFBundleShortVersionString raw support/Info.plist)"
git tag -a "v$release_version" -m "Glance $release_version"
git push origin "v$release_version"
```

The workflow creates the release only after every signing, notarization, appcast generation, and verification step succeeds. The signed appcast is published as an immutable release asset at a stable URL that installed copies of Glance check automatically. The latest DMG is available at:

```text
https://github.com/atchad/glance/releases/latest/download/Glance.dmg
```

Published release assets are available directly from the public repository. The repository must be public before shipping the first Sparkle-enabled release so installed apps can fetch the appcast without GitHub authentication. Each release also includes a signed PKG, signed `appcast.xml`, and `SHA256SUMS.txt` for independent verification.
