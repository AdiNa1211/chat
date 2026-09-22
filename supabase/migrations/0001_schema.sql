-- Phase 0 schema. Mirrors Section 6 of the architecture spec.
-- All content/body/caption columns are E2EE ciphertext (bytea); Postgres
-- and Supabase staff never see plaintext. Comments mark encrypted vs.
-- plaintext-safe columns per table.

create extension if not exists pgcrypto;

-- Profiles: public-safe fields only; auth.users (Supabase-managed) holds email/phone
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  display_name text not null,
  avatar_url text,
  status text,
  last_seen_at timestamptz,
  is_online boolean not null default false,
  created_at timestamptz not null default now()
);
create index idx_profiles_username on profiles (username);

-- One row per logged-in device/install; identity_public_key is the E2EE identity key.
create table devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  device_name text not null,
  platform text not null check (platform in ('android', 'ios', 'web')),
  identity_public_key bytea not null,
  signed_prekey bytea not null,
  signed_prekey_signature bytea not null,
  registration_id integer not null,
  push_token text,
  last_active_at timestamptz not null default now(),
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, id)
);
create index idx_devices_active on devices (user_id) where revoked_at is null;

-- One-time prekeys, consumed atomically on first use (X3DH); never reused.
create table one_time_prekeys (
  id bigint generated always as identity primary key,
  device_id uuid not null references devices(id) on delete cascade,
  key_id integer not null,
  public_key bytea not null,
  consumed_at timestamptz,
  unique (device_id, key_id)
);
create index idx_otp_available on one_time_prekeys (device_id) where consumed_at is null;

create table conversations (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('direct', 'group')),
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now()
);

create table conversation_members (
  conversation_id uuid not null references conversations(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  joined_at timestamptz not null default now(),
  muted_until timestamptz,
  last_read_message_id uuid,
  primary key (conversation_id, user_id)
);
create index idx_conversation_members_user on conversation_members (user_id);

create table messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  sender_id uuid not null references profiles(id),
  sender_device_id uuid not null references devices(id),
  ciphertext bytea not null,
  message_type text not null check (message_type in ('text', 'media', 'system')),
  reply_to_message_id uuid references messages(id),
  client_sent_at timestamptz not null,
  server_received_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_for_everyone_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);
create index idx_messages_conversation_order on messages (conversation_id, server_received_at desc);
create index idx_messages_expiring on messages (conversation_id) where expires_at is not null;

create table message_attachments (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references messages(id) on delete cascade,
  storage_path text not null,
  encrypted_metadata bytea not null,
  size_bytes bigint not null,
  chunk_count integer not null,
  content_hash_ciphertext bytea not null,
  created_at timestamptz not null default now()
);
create index idx_attachments_message on message_attachments (message_id);

create table message_reactions (
  message_id uuid not null references messages(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  encrypted_reaction bytea not null,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

create table read_receipts (
  message_id uuid not null references messages(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  status text not null check (status in ('delivered', 'read')),
  status_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

create table pinned_messages (
  conversation_id uuid not null references conversations(id) on delete cascade,
  message_id uuid not null references messages(id) on delete cascade,
  pinned_by uuid not null references profiles(id),
  pinned_at timestamptz not null default now(),
  primary key (conversation_id, message_id)
);

create table blocked_users (
  blocker_id uuid not null references profiles(id) on delete cascade,
  blocked_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);

create table user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references profiles(id),
  reported_id uuid not null references profiles(id),
  reason text not null,
  message_id uuid references messages(id),
  created_at timestamptz not null default now()
);

create table privacy_settings (
  user_id uuid primary key references profiles(id) on delete cascade,
  last_seen_visibility text not null default 'contacts'
    check (last_seen_visibility in ('everyone', 'contacts', 'nobody')),
  profile_photo_visibility text not null default 'contacts',
  read_receipts_enabled boolean not null default true,
  typing_indicator_enabled boolean not null default true
);

-- Signal Protocol per-conversation, per-device ratchet state — itself
-- encrypted with a key held only in that device's secure storage.
create table encryption_key_material (
  device_id uuid not null references devices(id) on delete cascade,
  conversation_id uuid not null references conversations(id) on delete cascade,
  wrapped_session_state bytea not null,
  updated_at timestamptz not null default now(),
  primary key (device_id, conversation_id)
);

-- Phase 2+ table, created now so Phase 1 migrations don't need a later
-- alter; unused until backup/recovery (Section 14) ships.
create table encrypted_backups (
  user_id uuid primary key references profiles(id) on delete cascade,
  storage_path text not null,
  backup_kdf_salt bytea not null,
  updated_at timestamptz not null default now()
);

-- Auto-maintain profiles.updated equivalent for last_active_at on devices.
create or replace function touch_device_last_active()
returns trigger
language plpgsql
as $$
begin
  new.last_active_at := now();
  return new;
end;
$$;
