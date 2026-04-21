# BARREL — Privacy Policy

_Last updated: 2026-04-20_

BARREL is built for coaches, parents, and players who want to track at-bat outcomes without handing over personal data. This policy explains exactly what we do (and don't do) with information that passes through the app.

## Data we collect

**None.** The app has no backend server, no analytics, and no third-party tracking. It does not transmit player names, at-bat outcomes, email addresses, device identifiers, or any other data off your device.

## What is stored on your device

The app stores three things locally on your iPhone:

1. **Your roster and at-bat history** — written to JSON files inside the app's own Documents directory. This data never leaves your device.
2. **Your sign-in credentials** — if you use the email + password option, an encrypted password hash and a display name are stored in the iOS Keychain. If you use "Sign in with Apple," only the Apple-issued user identifier and the display name Apple returns are stored in the Keychain.
3. **App preferences** — appearance mode (light/dark/system) and a few UI toggles, stored via `UserDefaults`.

All three locations are sandboxed to the app by iOS. Other apps cannot read them. iCloud backups may include this data if you have iCloud Backup enabled for your device, but the app itself never uploads anything.

## Sign in with Apple

When you choose "Sign in with Apple," authentication is performed by Apple's system. The app only receives the stable user identifier and, on first sign-in, the display name and email you authorize Apple to share. This information is stored locally in the iOS Keychain, not sent to any server.

## Children's privacy

The app is designed for all ages, and we do not knowingly collect any data from anyone — including children under 13. Because no data leaves the device, COPPA and GDPR obligations related to data collection, storage, and transfer do not apply.

## Third parties

There are no third-party SDKs, analytics services, crash reporters, or advertising frameworks in the app.

## Changes to this policy

If this ever changes — for example, if a future version adds an optional cloud-sync feature — this document will be updated and the app version that introduces the change will surface the updated policy before requesting any new permissions.

## Contact

Questions or concerns: divinejdavis@gmail.com
