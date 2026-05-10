# BARREL — Privacy Policy

_Last updated: 2026-05-10_

BARREL ("Barrel," "we," "us") is an iOS app for coaches, parents, and players to track at-bat outcomes and get AI feedback on swings. This policy explains what we collect, why, where it goes, and how to delete it.

## Summary

- We collect only what we need to run the app: an account identifier, the swing media you choose to analyze, the AI feedback we generate for you, your in-app chat with the AI, your subscription state, and basic in-app usage events.
- Your roster and at-bat history stay **on your device** unless you explicitly opt into a cloud-sync feature (none today).
- We use three sub-processors: **Supabase** (auth, database, storage), **Anthropic** (Claude AI feedback), and **Apple** (Sign in with Apple, StoreKit, App Store).
- We do **not** sell your data, run third-party advertising or analytics SDKs, or track you across other apps or websites.

## Data we collect and why

| Data | When | Where it's stored | Purpose |
|---|---|---|---|
| Email address | Account creation (email signup or Sign in with Apple if you authorize sharing) | Supabase Auth | Identify your account, sign you in |
| Password (hashed) | Email signup only | Supabase Auth (bcrypt) | Sign-in; the plaintext is never stored |
| Apple user identifier | Sign in with Apple | Supabase Auth + iOS Keychain | Sign-in |
| Display name | Account creation | Supabase Auth metadata + iOS Keychain | Greeting in the UI |
| Swing photo or video you submit for analysis | When you tap "Analyze swing" | Supabase Storage (private bucket, path scoped to your user ID) | Sent to the Claude API to generate feedback |
| AI feedback text | Generated when you analyze a swing or chat | Supabase database (`swing_analyses`, `chat_messages`) | Show feedback in the app and in your history |
| Your AI chat messages | When you send a chat | Supabase database (`chat_messages`) | Conversation history |
| Subscription tier and Apple transaction ID | When you purchase or restore a subscription | Supabase database (`subscriptions`) | Enforce quota and entitlements |
| Quota counters (number of swings/questions used per day and month) | Each AI request | Supabase database (`usage_counters`, `daily_usage`) | Enforce free/Standard/Pro tier limits |
| Product interaction events (e.g., screen viewed, "Analyze swing" tapped, paywall shown, subscribe completed) | While you use the app | Supabase database (`app_events`) | Understand which features are used and where users get stuck so we can improve the app |
| App version, OS version, and device model | Attached to product interaction events | Supabase database (`app_events`) | Diagnose issues by environment |

We do **not** collect: location, contacts, browsing history, advertising identifiers (IDFA), health data, or financial information beyond the Apple-issued transaction ID. We do not record audio.

### Linked to your account
All of the above is linked to your account so we can show you your own history and enforce your subscription. None of it is used for cross-app tracking.

## Stored only on your device

The following stay on your iPhone in the app's sandboxed storage and are never uploaded by Barrel:

- **Roster and at-bat history** — JSON files in the app's Documents directory
- **Sign-in metadata** — display name, account method, and (for Sign in with Apple) the Apple user identifier in the iOS Keychain
- **App preferences** — appearance mode (light/dark/system) and language preference in `UserDefaults`

iCloud backups may include this data if you have iCloud Backup enabled for your device.

## Sub-processors

| Provider | Purpose | Region |
|---|---|---|
| **Supabase Inc.** | Authentication, Postgres database, object storage, edge functions | United States (default region) |
| **Anthropic, PBC** | Claude AI processes the swing media and chat messages you submit and returns feedback | United States |
| **Apple Inc.** | Sign in with Apple, StoreKit subscription processing, App Store delivery | Per Apple's policy |

Submitted swing media and chat content are sent to Anthropic for processing. Per the Anthropic API agreement we use, this content is **not** used to train Anthropic's models.

## Sign in with Apple

If you choose Sign in with Apple, Apple handles authentication. Barrel receives the stable Apple user identifier and, on first sign-in, the display name and email you authorize Apple to share (this can be a private relay address). These are stored in Supabase Auth and the iOS Keychain.

## Children's privacy

Barrel is not directed at children under 13 and we do not knowingly collect personal information from children under 13. Anthropic's API terms also require users to be at least 13. The App Store age rating for Barrel is 13+. If you are a parent or guardian and believe your child under 13 has provided us with information, contact us and we will delete it.

## Your rights and how to delete your data

You can:

- **Delete your account and all server-side data** from inside the app (tap the profile icon in the top right → "Delete Account"). This permanently removes your row from `auth.users` and cascades to every related table (`subscriptions`, `usage_counters`, `daily_usage`, `swing_analyses`, `chat_messages`, `app_events`) and removes your uploaded swing media from Supabase Storage.
- **Export or correct your data** by emailing the address below.
- **Withdraw consent** for further processing by deleting the app or your account.

Residents of the EU/UK (GDPR) and California (CCPA/CPRA) have the additional rights to access, rectify, port, and object to processing of their data, and to opt out of any "sale" or "sharing" of personal information. We do not sell or share personal information for cross-context behavioral advertising.

## Retention

We keep account data for as long as your account exists. When you delete your account the cascade above runs immediately; backups are purged on Supabase's standard rolling retention (typically 7 days for daily backups). Aggregated, non-identifiable counts (e.g., "how many users tapped the paywall this week") may be retained indefinitely.

## Security

- All network traffic is over HTTPS/TLS.
- Supabase Storage and database tables enforce row-level security so that users can only read their own rows.
- Sensitive operations (AI calls, subscription updates, quota mutation) run inside server-side edge functions using a service-role key that never leaves the server.
- The publishable key embedded in the iOS app only grants anonymous-role access.

## Changes

If we change what we collect or who processes it, we'll update this document and the in-app "What's New" before the change takes effect.

## Contact

Questions, deletion requests, or privacy concerns: **divinejdavis@gmail.com**
