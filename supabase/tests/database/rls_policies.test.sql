-- RLS/security tests (Section 18) for the Phase 0+1 schema, using pgTAP.
--
-- Run locally with the Supabase CLI (this file is NOT executable from the
-- sandbox this project was authored in — no local Postgres/Supabase CLI
-- was reachable there; run it on your machine as the first verification
-- step alongside `flutter test`):
--   supabase start
--   supabase test db
--
-- Each test impersonates a specific authenticated user the same way
-- PostgREST does in production: `set local role authenticated` plus
-- `request.jwt.claim.sub`, which is exactly what `auth.uid()` reads. No
-- application code is exercised here — this is a direct test of the SQL
-- policies in 0001_schema.sql / 0002_rls.sql, independent of the Dart
-- client ever getting them right.

begin;
select plan(16);

-- ---------------------------------------------------------------------------
-- Fixtures: two users (alice, bob) and a third (mallory) who is not a
-- member of anything, plus one direct conversation between alice and bob.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'alice@example.test'),
  ('00000000-0000-0000-0000-000000000002', 'bob@example.test'),
  ('00000000-0000-0000-0000-000000000003', 'mallory@example.test');

insert into public.profiles (id, username, display_name) values
  ('00000000-0000-0000-0000-000000000001', 'alice', 'Alice'),
  ('00000000-0000-0000-0000-000000000002', 'bob', 'Bob'),
  ('00000000-0000-0000-0000-000000000003', 'mallory', 'Mallory');

insert into public.devices (id, user_id, device_name, platform, identity_public_key, signed_prekey, signed_prekey_signature, registration_id) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Alice iPhone', 'ios', '\x00', '\x00', '\x00', 1),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 'Bob Pixel', 'android', '\x00', '\x00', '\x00', 2);

insert into public.one_time_prekeys (device_id, key_id, public_key) values
  ('10000000-0000-0000-0000-000000000002', 1, '\x00');

insert into public.conversations (id, type, created_by) values
  ('20000000-0000-0000-0000-000000000001', 'direct', '00000000-0000-0000-0000-000000000001');

insert into public.conversation_members (conversation_id, user_id, role) values
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'owner'),
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'member');

insert into public.messages (id, conversation_id, sender_id, sender_device_id, ciphertext, message_type, client_sent_at) values
  ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '\xdeadbeef', 'text', now());

insert into public.blocked_users (blocker_id, blocked_id) values
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003');

-- ---------------------------------------------------------------------------
-- messages: the single most safety-critical policy in this schema — a
-- non-member must never see ciphertext for a conversation they're not in.
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  (select count(*)::int from public.messages where conversation_id = '20000000-0000-0000-0000-000000000001'),
  1,
  'alice (a member) can see the message in her conversation'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';

select is(
  (select count(*)::int from public.messages where conversation_id = '20000000-0000-0000-0000-000000000001'),
  0,
  'mallory (not a member) sees zero messages from a conversation she is not in'
);

select is(
  (select count(*)::int from public.conversation_members where conversation_id = '20000000-0000-0000-0000-000000000001'),
  0,
  'mallory cannot even see who the members of a conversation she is not in are'
);

select throws_ok(
  $$ insert into public.messages (id, conversation_id, sender_id, sender_device_id, ciphertext, message_type, client_sent_at)
     values ('30000000-0000-0000-0000-000000000099', '20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', '\x00', 'text', now()) $$,
  '42501',
  'mallory cannot insert a message into a conversation she is not a member of'
);

-- ---------------------------------------------------------------------------
-- messages: a member cannot spoof another member's sender_id.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select throws_ok(
  $$ insert into public.messages (id, conversation_id, sender_id, sender_device_id, ciphertext, message_type, client_sent_at)
     values ('30000000-0000-0000-0000-000000000098', '20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', '\x00', 'text', now()) $$,
  '42501',
  'alice cannot insert a message with sender_id spoofed as bob, even though she is a member'
);

select lives_ok(
  $$ insert into public.messages (id, conversation_id, sender_id, sender_device_id, ciphertext, message_type, client_sent_at)
     values ('30000000-0000-0000-0000-000000000097', '20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '\x00', 'text', now()) $$,
  'alice can insert a message with her own sender_id in a conversation she is a member of'
);

-- ---------------------------------------------------------------------------
-- devices: full rows (including key material) are only visible to their
-- own owner, never to another user via a broad select.
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from public.devices where user_id = '00000000-0000-0000-0000-000000000002'),
  0,
  'alice cannot select bobs device row directly (only her own devices are selectable)'
);

select is(
  (select count(*)::int from public.devices where user_id = '00000000-0000-0000-0000-000000000001'),
  1,
  'alice can select her own device row'
);

-- Public-safe device discovery/prekey-bundle RPCs remain available even
-- though the direct table select above is denied.
select is(
  (select count(*)::int from public.list_user_device_ids('00000000-0000-0000-0000-000000000002')),
  1,
  'list_user_device_ids still lets alice discover bobs active device ids via the security-definer RPC'
);

select is(
  (select device_id::text from public.get_device_prekey_bundle('10000000-0000-0000-0000-000000000002')),
  '10000000-0000-0000-0000-000000000002',
  'get_device_prekey_bundle still exposes bobs PUBLIC key material via the security-definer RPC'
);

-- ---------------------------------------------------------------------------
-- one_time_prekeys: never directly selectable for someone else's device,
-- even though the RPC above can consume one server-side.
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from public.one_time_prekeys where device_id = '10000000-0000-0000-0000-000000000002'),
  0,
  'alice cannot directly select bobs one-time prekeys (must go through consume_one_time_prekey)'
);

-- ---------------------------------------------------------------------------
-- blocked_users: a user can never see who has blocked *them*.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';

select is(
  (select count(*)::int from public.blocked_users where blocked_id = '00000000-0000-0000-0000-000000000003'),
  0,
  'mallory cannot see that alice has blocked her'
);

-- ---------------------------------------------------------------------------
-- user_reports: write-only from the client, never readable back.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select lives_ok(
  $$ insert into public.user_reports (id, reporter_id, reported_id, reason)
     values ('40000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 'spam') $$,
  'alice can file a report'
);

select is(
  (select count(*)::int from public.user_reports where id = '40000000-0000-0000-0000-000000000001'),
  0,
  'alice cannot read back the report she just filed (no select policy for authenticated)'
);

-- ---------------------------------------------------------------------------
-- storage.objects (chat-media): only a conversation member may read an
-- attachment's ciphertext blob, keyed by the {conversation_id}/... path
-- convention SupabaseMediaRepository uses.
-- ---------------------------------------------------------------------------
insert into storage.objects (bucket_id, name, owner) values
  ('chat-media', '20000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/attachment.enc', '00000000-0000-0000-0000-000000000001');

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

select is(
  (select count(*)::int from storage.objects where bucket_id = 'chat-media' and name like '20000000-0000-0000-0000-000000000001/%'),
  1,
  'bob (a conversation member) can see the chat-media object for that conversation'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';

select is(
  (select count(*)::int from storage.objects where bucket_id = 'chat-media' and name like '20000000-0000-0000-0000-000000000001/%'),
  0,
  'mallory (not a member) cannot see the chat-media object for a conversation she is not in'
);

select * from finish();
rollback;
