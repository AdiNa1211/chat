# Secure Chat — Phase 0 + Phase 1 (MVP)

Flutter E2EE chat app (Signal Protocol: X3DH + Double Ratchet) on Supabase.
Implements, in the order you specified: Foundation → Auth → Device/Identity
Keys → 1:1 E2EE → Text Chat → Encrypted Files → Offline Sync → Push →
Security/RLS Tests. Groups, multi-device, calls, and backup are **out of
scope** here — Phase 2+.

## This was never compiled

No Flutter/Dart SDK and no pub.dev access were reachable from the sandbox
this was written in, so **none of this has been run through `flutter
analyze`, `flutter test`, `flutter pub get`, or a compiler** — every file
was hand-written and hand-reviewed against the pinned package versions'
documented APIs, not verified against them. A few files carry inline
comments flagging the specific calls most likely to need a small
signature fix once you can actually build (`sodium_libs`'s stream-push
API in `file_crypto_service.dart`, `libsignal_protocol_dart`'s store
interfaces in `signal_store_adapter.dart`). Treat the first local
build as step one, not a formality. (`flutter_local_notifications`'s
API in `local_notification_service.dart` has the same caveat but is
currently dormant — see "Push notifications (disabled for now)".)

## First steps, in order

1. **Scaffold the native platform projects** — this repo has no
   `android/`, `ios/`, or `web/` directory yet (no Flutter SDK was
   available to generate them). Run, from this folder:
   ```
   flutter create . --project-name secure_chat_app --org <your.reverse.domain>
   ```
   This only adds the platform runner folders; it will not touch `lib/`.
2. `flutter pub get`
3. `dart run build_runner build --delete-conflicting-outputs` (generates
   every `*.g.dart` — Drift tables/DAOs — referenced by `part` directives
   but not checked in)
4. `flutter analyze` — fix whatever the three files above flag
5. `flutter test` — the crypto/RLS test suite below
6. Push notifications are currently **disabled** (commented out, not
   deleted) — see "Push notifications (disabled for now)" below before
   you need step 6 to be "add Firebase."

## Backend setup

```
supabase init          # if you haven't already
supabase link --project-ref <your-project-ref>
supabase db push       # applies supabase/migrations/0001_schema.sql, 0002_rls.sql
```
The `push-notify` Edge Function exists in `supabase/functions/` but is not
deployed or wired up by these steps — see "Push notifications (disabled
for now)" below.

Buckets (`avatars`, `chat-media`, `encrypted-backups`) and their storage
policies are created by `0002_rls.sql`.

## Push notifications (disabled for now)

Dropped from this build rather than deleted: Supabase has no native
push-delivery service of its own (see its own docs on this — Edge
Function + FCM/APNs is the standard pattern), so wiring push up at all
means pulling in Firebase purely as the FCM transport. That felt like
unnecessary weight for right now.

Everything for it is still in the tree, commented out rather than
removed:
- `pubspec.yaml` — the 3 `firebase_*`/`flutter_local_notifications`
  lines
- `lib/features/notifications/data/push_token_service.dart` and
  `local_notification_service.dart` — whole-file block comments
- `lib/core/di/injection_container.dart` — the registrations at the
  bottom
- `lib/app.dart` — the `getIt<PushTokenService>().start()` call
- `lib/main.dart` — the `Firebase.initializeApp()` block
- `supabase/functions/push-notify/index.ts` — untouched, just not
  deployed or wired to a webhook

To bring it back: uncomment all of the above (each spot says so),
then follow the Backend setup section's original Edge Function steps
(`supabase functions deploy push-notify`, set `PUSH_WEBHOOK_SECRET`/
`FCM_SERVER_KEY`, add the Database Webhook in Studio) and run
`flutterfire configure` for the client-side Firebase config.

## Running the app

```
flutter run \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon/publishable key>
```
`lib/core/network/supabase_config.dart` reads these; the app throws on
startup if either is missing, rather than silently pointing at nothing.

## Tests

- `test/core/**` — pure-Dart/pure-Signal-Protocol unit tests: identity
  key generation, X3DH session establishment, Double Ratchet round-trips
  (both directions, several messages), tamper detection, and the
  identity-changed ("safety number changed") rejection path — all
  against the app's real `SessionManager`/`IdentityKeyService`/
  `SignalStoreAdapter` classes, backed by an in-memory Drift database
  instead of SQLCipher (no native encryption dependency needed for these
  to run). Also covers `device_id_codec.dart`, `ciphertext_envelope.dart`,
  `Sensitive`, and `Result`.
- `test/features/chat_1to1/chat_thread_cubit_test.dart` — bloc_test
  coverage of `ChatThreadCubit`'s message/typing stream handling and
  `sendMessage`. `pickAndSendFile()`'s OS file-picker step isn't unit
  tested — that needs an integration/device test, noted inline.
- `supabase/tests/database/rls_policies.test.sql` — pgTAP RLS tests
  covering the schema's core security properties (message confidentiality
  across non-members, sender-id spoofing, device key-material isolation,
  the one-time-prekey consume-only-via-RPC boundary, `blocked_users`
  one-directional visibility, `user_reports` write-only access, and
  `chat-media` storage object isolation). Run with `supabase test db`
  after `supabase start`. **Not executed anywhere in this session** — no
  local Postgres/Supabase CLI was reachable from the sandbox — run this
  before trusting the RLS policies in production.
- `FileCryptoService` (libsodium streaming encryption) has no unit test
  here: `sodium_libs` needs native libsodium bound in, which isn't
  available under plain `flutter test` without a device/integration
  test. Verify it manually (encrypt → decrypt round-trip on a real file,
  plus a deliberately truncated/corrupted ciphertext) on-device first.

## Known Phase 1 gaps (by design, not oversight)

- **Media sharing is mobile/desktop only.** `FileCryptoService` streams
  through `dart:io File`, which isn't Web-compatible; the attach button
  is disabled on Web (`chat_thread_cubit.dart`).
- **Fan-out is to one device per contact**, not every device they own
  (`chat_repository_impl.dart` / `supabase_media_repository.dart`) — full
  multi-device fan-out is Phase 2, per your roadmap.
- **Media messages advance the ratchet once, not twice** — the wrapped
  file key + metadata are bundled into a single encrypted payload rather
  than the spec's stricter two-ciphertext split (documented in
  `supabase_media_repository.dart`).
- **Push notifications are disabled** (commented out, not deleted) —
  see "Push notifications (disabled for now)" above. The dormant
  Edge Function still uses the legacy FCM HTTP API (server-key auth)
  rather than the HTTP v1 API (OAuth2/service-account) — flagged as a
  Phase 2 hardening item in the function itself, whenever push comes
  back.
- **Web's local database** (SQLCipher isn't available in a browser) is
  stubbed, not implemented — `app_database.dart`'s doc comment names the
  WASM/IndexedDB path this needs; Web is not really usable end-to-end
  yet despite being a named target.
