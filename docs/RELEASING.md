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

Export the Developer ID Application identity and Developer ID Installer identity, including each private key, from Keychain Access as separate password-protected `.p12` files. Encode each file and send the encoded value directly to GitHub Secrets:

```sh
base64 -i DeveloperIDApplication.p12 -o DeveloperIDApplication.p12.base64
gh secret set DEVELOPER_ID_APPLICATION_P12_BASE64 --env release < DeveloperIDApplication.p12.base64
gh secret set DEVELOPER_ID_APPLICATION_P12_PASSWORD --env release

base64 -i DeveloperIDInstaller.p12 -o DeveloperIDInstaller.p12.base64
gh secret set DEVELOPER_ID_INSTALLER_P12_BASE64 --env release < DeveloperIDInstaller.p12.base64
gh secret set DEVELOPER_ID_INSTALLER_P12_PASSWORD --env release
```

Create a team App Store Connect API key with the minimum role that can submit software for notarization. Download its `.p8` file once, then store it and its identifiers:

```sh
base64 -i AuthKey_KEY_ID.p8 -o AuthKey_KEY_ID.p8.base64
gh secret set APP_STORE_CONNECT_KEY_BASE64 --env release < AuthKey_KEY_ID.p8.base64
gh secret set APP_STORE_CONNECT_KEY_ID --env release
gh secret set APP_STORE_CONNECT_ISSUER_ID --env release
```

Delete local exported credential files after confirming the workflow can sign a release. Base64 is encoding, not encryption; GitHub Secrets provides storage protection.

In the repository release settings, enable immutable releases when available. This locks a published tag and its assets and adds a release attestation.

## Publish a release

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `support/Info.plist`.
2. Merge the tested change to `main` and wait for CI to pass.
3. Create and push an annotated tag matching the short version exactly:

```sh
git tag -a v0.1.4 -m "Glance 0.1.4"
git push origin v0.1.4
```

The workflow creates the release only after every signing, notarization, and verification step succeeds. The latest DMG is available to authenticated repository users at:

```text
https://github.com/atchad/glance/releases/latest/download/Glance.dmg
```

Because the repository is private, GitHub requires an account with repository access. Distribute the downloaded signed artifact through a separate company-approved channel for users who should not receive source access.
