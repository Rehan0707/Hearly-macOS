# Hearly account integration

Status checked September 16, 2026: the project endpoint at
`https://hlwzcklxskvfdmohyzxg.supabase.co/auth/v1/health` responds with HTTP 401
when called without an API key. This confirms the gateway is reachable, **not**
that authentication, providers, or application tables are configured.

No `Resources/Backend.json` or matching public client key was found in the scoped
repository configuration or the deployed public Hearly website bundle. The
Supabase dashboard link alone does not provide a client key. No database rows
were read or changed, and no sign-in emails were sent during this check.

## Required project setup

1. Obtain this project's **publishable** key (or legacy **anon** key) from the
   Supabase dashboard. Never put a secret key, service-role key, database
   password, or dashboard access token in the desktop application.
2. Create `macos/Resources/Backend.json` from `Backend.example.json`, setting
   `url` to `https://hlwzcklxskvfdmohyzxg.supabase.co` and `publishableKey` to that
   public key. The build script copies this configuration into the app.
3. In Authentication → URL Configuration, allow `hearly://auth/callback`.
4. Enable and configure Google and Apple providers if those login buttons are
   to be offered. Supabase provider credentials remain in the dashboard, never
   in the native app.
5. For the native email-code flow, configure the Magic Link email template to
   include `{{ .Token }}`. Supabase's default OTP request sends a magic link;
   the current native form verifies a code. Check SMTP delivery/restrictions
   using an authorized tester before declaring this flow ready.
6. Inspect existing `public.hearly_profiles`, policies, and RPC definitions
   before applying `supabase/migrations/202609150001_hearly_accounts.sql`.
   The migration is prepared locally and has **not** been applied here. It
   creates account display-name metadata with own-user row-level policies.
   Do not blindly rerun it: its policy creation statements are not idempotent.
7. Verify two separate test accounts can access only their own profile rows,
   and verify email, Google, Apple, token refresh, relaunch, and local sign-out.
   These live tests remain outstanding.

## What is stored where

- Supabase Auth: account/session identity; session credentials are saved in
  macOS Keychain by the native app.
- Supabase `hearly_profiles`: authenticated user's display name via
  `hearly_update_profile`; no voice audio or embeddings are uploaded.
- Local SQLite: voice profiles and transcript text, encrypted with AES-GCM
  before storage; the encryption key lives in Keychain. This is not cloud
  transcript/profile sync.
- `supabase/functions/waitlist`: email delivery through Resend, not an app
  account/profile database implementation.

The native service rejects malformed URLs and server-only keys, records the
session's project to avoid cross-project refresh, reuses valid sessions, and
serializes token rotation before authenticated profile updates. Call
`account.signOutLocally()` from the app's sign-out action so pending refreshes
cannot save a session again. This is local sign-out, not remote session
revocation across other devices.

## Offline verification

From `macos/`, compile the standalone contracts with the active Xcode SDK:

```sh
xcrun swiftc -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macos13 \
  Sources/HearlyMac/Services/Accounts/AccountService.swift \
  Sources/HearlyMac/Services/Persistence/LocalDatabase.swift \
  Tests/AccountContractSmoke.swift -o /tmp/hearly-account-contract-smoke
/tmp/hearly-account-contract-smoke
```

These tests exercise configuration validation, rejection of secret/service-role
keys, token-expiration handling, Codable compatibility, and OAuth callback
validation. They do not access Keychain or the network, and do not substitute
for live integration testing.

Sources: [Supabase sessions](https://supabase.com/docs/guides/auth/sessions),
[passwordless email sign-in](https://supabase.com/docs/guides/auth/auth-email-passwordless).
