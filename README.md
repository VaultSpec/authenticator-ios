# VaultSpec Authenticator for iOS

SwiftUI two-factor authenticator built on iOS 26 Liquid Glass, for iPhone, iPad and Mac
(Mac Catalyst, optimised for Mac).

## Requirements

- Xcode 26 or later
- iOS 26 / iPadOS 26 or later, or macOS 26 or later

Open `VaultSpec.xcodeproj` and run the **VaultSpec** scheme. Set your team under Signing &
Capabilities before running on a device.

## Features

- Vault protected by a password, with optional Face ID / Touch ID unlock
- Time-based codes (TOTP, RFC 6238) with SHA-1, SHA-256 and SHA-512, 6 or 8 digits, 30 or 60 s
- Add accounts by scanning a QR code (VisionKit), pasting an `otpauth://` link, or typing the key
- Search and categories: Personal, Work, Social and your own (All shows every account)
- Tap a card to copy its code; the clipboard entry is device-only and expires after 60 s
- Locks whenever the app goes to the background; the app switcher shows a privacy cover
- Encrypted cloud backup and restore through a VaultSpec account, compatible with the Android app
- Scan & Connect: set up a new iPhone, iPad or Android phone by scanning a particle cloud shown on
  another device (Settings → Connect a Device, Setup → Use Another Device)
- Adapts to the screen: one to several columns of cards, side-by-side lock and setup screens on
  an iPhone in landscape, resizable windows on iPad and Mac, Touch ID on Macs that have it
- Keyboard shortcuts: ⌘N add account, ⌘, settings, ⌃⌘L lock

## Design

Account cards, category chips, buttons and the search field use Liquid Glass (`glassEffect`,
`GlassEffectContainer`, glass button styles) over an animated mesh-gradient backdrop, in both
light and dark mode. The backdrop stops animating when Reduce Motion is on.

## Security model

- A random 256-bit **master key** encrypts the account list with AES-256-GCM. The encrypted
  file lives in Application Support with complete file protection.
- The master key is stored in the Keychain **wrapped** with a key derived from the vault
  password (PBKDF2-HMAC-SHA256, 600,000 rounds). The password itself is never stored.
- With biometrics on, a second copy of the master key is kept in the Keychain behind
  `.biometryCurrentSet`, so re-enrolling Face ID or Touch ID disables it.
- Keychain items are `ThisDeviceOnly`, so they are excluded from backups and device transfers.

## VaultSpec Cloud

Uses the same API as the Android app (`https://api.vaultspec.in`, source in the
`authenticator-BE` repository).

- **Account:** email and account password, then a six-digit code sent by email. The session
  (short-lived access token, single-use refresh token) is kept in the Keychain.
- **Encryption:** backups are encrypted on the device with a key derived from the **vault
  password** using scrypt (N = 32768, r = 8, p = 1) and AES-256-GCM. The server only stores
  ciphertext. The derived key and its salt are kept in the Keychain so automatic backups work after
  a Face ID / Touch ID unlock; the password itself is never stored.
- **Format:** the same JSON as the Android app's `.vsbk` backups, so a backup made on Android
  restores on iPhone, iPad and Mac and the other way round.
- **Key id:** each upload carries the first 8 bytes of SHA-256(salt). After a vault password
  change the app uploads under a new key id, and the server deletes every backup made with the old
  password. The server keeps the newest three.
- **When:** two seconds after accounts change, and from **Back Up Now**. A failed upload is retried
  on the next change or unlock.
- **Restore:** from the setup screen (the backup's vault password becomes the new vault's
  password) or from Settings (adds the accounts, skipping ones already on the device).
- **Account deletion:** Settings → Delete Cloud Account removes the account and all its backups.

## Project layout

| Folder | Contents |
|---|---|
| `VaultSpec/App` | App entry point, root view, privacy cover |
| `VaultSpec/Model` | `Account`, `otpauth://` parsing |
| `VaultSpec/Crypto` | Base32, TOTP, vault encryption, scrypt |
| `VaultSpec/Cloud` | VaultSpec Cloud API client, backup format, `CloudStore` |
| `VaultSpec/Storage` | Keychain wrapper, `VaultStore` |
| `VaultSpec/Views` | Setup, lock, home, account card, add account, scanner, settings, cloud sign-in and restore |
| `VaultSpec/Design` | Backdrop and shared components |
| `VaultSpecTests` | Unit tests (Swift Testing) |
| `Config` | Mac App Sandbox entitlements |
| `marketing` | Teaser posters |

The project uses folder-synchronised groups, so new files in these folders are picked up
without editing the project file.

## Tests

```bash
xcodebuild test -project VaultSpec.xcodeproj -scheme VaultSpec \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Covers the RFC 6238 test vectors for all three algorithms, Base32, `otpauth://` parsing,
AES-GCM, PBKDF2, the RFC 7914 scrypt vectors, and opening a backup written in the Android app's
format.

An end-to-end cloud test (sign in, back up, restore, retention, password change, account
deletion) runs when a backend is available. Start `authenticator-BE` locally with a review
account so no email is needed:

```bash
PORT=8787 REVIEW_EMAIL=ios-test@vaultspec.local REVIEW_CODE=246810 \
  node --env-file=.env --import tsx src/index.ts
```

then run the tests with `TEST_RUNNER_VAULTSPEC_CLOUD_TEST_URL=http://127.0.0.1:8787` set.

## Debug launch arguments

Compiled out of release builds.

| Argument | Effect |
|---|---|
| `-demoVault` | Replaces any existing vault with seven sample accounts (password `demo-vault-1`) |
| `-demoLocked` | With `-demoVault`, starts on the lock screen |
| `-colorScheme dark` / `light` | Forces the appearance |
| `-orientation landscape` | Rotates an iPhone to landscape |
| `-cloudBaseURL http://127.0.0.1:8787` | Points VaultSpec Cloud at a local server |

## Not yet built

- Importing and exporting `.vsbk` backup files
- Scanning a QR code from an image on the Mac (the camera scanner is iPhone and iPad only)
- Brand icons for services (cards currently show a coloured initial)
