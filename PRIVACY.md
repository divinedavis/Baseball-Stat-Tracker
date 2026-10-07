# BARREL — Privacy Policy

_Last updated: October 7, 2026_

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
| Swing photo or video you submit for analysis (this usually shows the player, who may be a child) | When you tap "Analyze swing" | Supabase Storage (private bucket, path scoped to your user ID); deleted as soon as the analysis finishes (successful or not), and any upload that never reached analysis is deleted automatically within 30 days | Sent to Anthropic's Claude API to generate feedback |
| Optional note you type with a swing | When you tap "Analyze swing" | Sent with the swing to Anthropic; the feedback is saved in `swing_analyses` | Context for the feedback |
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

Barrel is marketed to coaches and parents of youth teams, including 9–12-year-old
teams, so much of the information in the app is **about children**. The app is
meant to be used by adults: the account holder should be a coach, parent or
guardian (or a player aged 13 or older). We do not knowingly let children under
13 create their own accounts; if we learn one has, we will delete it.

**What is collected about players, and by whom.** All of it is entered by the
coach or parent who holds the account:

- **Roster and stats — on the device only.** Player name, jersey number,
  position, age, team, level, batting side, at-bat results and game sessions
  are saved in the app's local storage on that iPhone (and in its iCloud
  backup, if enabled). Barrel does not upload them to our servers or send them
  to Anthropic.
- **Swing photos and videos — uploaded.** When the account holder taps
  "Analyze swing", the photo or video (which usually shows the player's body
  and may show their face) is uploaded to our Supabase storage, and the image
  (or a frame from the video) is sent to **Anthropic** to generate coaching
  feedback. The media is deleted from Supabase storage as soon as the analysis
  finishes; anything left behind (for example if the app was closed
  mid-upload) is deleted automatically within 30 days. Only the text
  feedback is kept.
  Any note typed with the swing, the AI feedback, and AI chat messages are
  stored in our Supabase database. Please don't type a child's full name or
  other identifying details into notes or chat — the AI does not need them.
- We do not collect a player's contact details, location, school or photos
  outside of the swings you choose to analyze, and nothing about a player is
  used for advertising, sold, or used to train AI models (Anthropic does not
  train on API content under our agreement).

**Parental rights.** A parent or guardian can at any time:

- **Review** what is stored — roster and stats are visible in the app; for
  swing media, AI feedback and chat, email us and we will send a copy of
  everything held on our servers for the account within 30 days.
- **Delete** it — in the app, tap the profile icon (top right) → **Delete
  Account**. This removes any swing photos and videos still in storage, deletes the
  analyses, chat, subscription and usage records, and wipes the roster and
  at-bat data on the device. A single player's roster entry and stats can be
  deleted from the roster list.
- **Refuse further collection** — stop using "Analyze swing" and AI chat; the
  stat tracker works without uploading anything.
- If a coach's account holds swing media of your child and you want it removed,
  email us with the team and approximate dates and we will work with the
  account holder to delete it within 30 days.

Contact for any request about a child's information: **divinejdavis@gmail.com**.

## Your rights and how to delete your data

You can:

- **Delete your account and all server-side data** from inside the app (tap the profile icon in the top right → "Delete Account"). This permanently removes your row from `auth.users` and cascades to every related table (`subscriptions`, `usage_counters`, `daily_usage`, `swing_analyses`, `chat_messages`, `app_events`) and removes your uploaded swing media from Supabase Storage.
- **Export or correct your data** by emailing the address below.
- **Withdraw consent** for further processing by deleting the app or your account.

Residents of the EU/UK (GDPR) and California (CCPA/CPRA) have the additional rights to access, rectify, port, and object to processing of their data, and to opt out of any "sale" or "sharing" of personal information. We do not sell or share personal information for cross-context behavioral advertising.

## Retention

Swing photos and videos are deleted when their analysis finishes, and in any case within 30 days of upload. We keep other account data for as long as your account exists. When you delete your account the cascade above runs immediately; backups are purged on Supabase's standard rolling retention (typically 7 days for daily backups). Aggregated, non-identifiable counts (e.g., "how many users tapped the paywall this week") may be retained indefinitely.

## Security

- All network traffic is over HTTPS/TLS.
- Supabase Storage and database tables enforce row-level security so that users can only read their own rows.
- Sensitive operations (AI calls, subscription updates, quota mutation) run inside server-side edge functions using a service-role key that never leaves the server.
- The publishable key embedded in the iOS app only grants anonymous-role access.

## Changes

If we change what we collect or who processes it, we'll update this document and the in-app "What's New" before the change takes effect.

## Contact

Questions, deletion requests, or privacy concerns: **divinejdavis@gmail.com**
