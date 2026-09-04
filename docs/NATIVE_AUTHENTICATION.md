# Native GitHub authentication

Glance's native sign-in uses GitHub's OAuth device flow. The application does not need or ship a
client secret, but release builds must contain the public client ID of a registered GitHub OAuth
App.

## Create the OAuth App

1. Open the GitHub account or organization that will own the application.
2. Go to **Settings → Developer settings → OAuth Apps → New OAuth App**.
3. Enter the application name `Glance`.
4. Enter the public Glance project or product page as the homepage URL.
5. Enter the same HTTPS URL as the authorization callback URL. Device flow does not redirect to
   this URL, but GitHub requires the field when the OAuth App is created.
6. Create the application, then open its settings and enable **Device Flow**.
7. Keep expiring user tokens enabled. Glance stores the refresh token in Keychain and refreshes the
   access token before it expires.
8. Copy the OAuth App's client ID. A client ID is public configuration, not a secret. Glance does
   not use the client secret.

The native flow requests `repo` and `read:org` so Glance can load public and private pull requests,
repository membership, and review requests from organizations the user can access.

## Configure a build

Pass the client ID only to the app-bundle build step:

```sh
GLANCE_GITHUB_OAUTH_CLIENT_ID=Iv1.example ./scripts/build-app.sh release
```

The build script writes the value to `Glance.app/Contents/Info.plist` as
`GlanceGitHubOAuthClientID`. It does not modify `support/Info.plist` or store the value in source.
If the value is absent, the native authorization service returns a configuration error while the
existing GitHub CLI credential provider remains available.

The release environment must define the repository/environment variable
`GLANCE_GITHUB_OAUTH_CLIENT_ID`. The release workflow fails before packaging if it is missing and
verifies that the client ID is present in the signed application bundle.

Do not add a client secret, access token, device code, or user code to source control, build logs,
release notes, test fixtures, preferences, or the pull-request cache.

## Credential storage

Native access and refresh tokens, along with their expiry dates, are stored together as a
generic-password item in the user's login Keychain. Glance
uses the service `app.glance.Glance.github-oauth` and the GitHub hostname as the account. Items use
the `AfterFirstUnlockThisDeviceOnly` accessibility class so they are available to the background
menu-bar app after login but do not migrate to another device through a backup.
