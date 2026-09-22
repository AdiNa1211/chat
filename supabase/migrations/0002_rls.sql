-- Row Level Security. Mirrors Section 7 of the architecture spec.
-- RLS is enabled on every table with no exceptions; the anon/publishable
-- key can only ever act as the authenticated auth.uid().

alter table profiles enable row level security;
alter table devices enable row level security;
alter table one_time_prekeys enable row level security;
alter table conversations enable row level security;
alter table conversation_members enable row level security;
alter table messages enable row level security;
alter table message_attachments enable row level security;
alter table message_reactions enable row level security;
alter table read_receipts enable row level security;
alter table pinned_messages enable row level security;
alter table blocked_users enable row level security;
alter table user_reports enable row level security;
alter table privacy_settings enable row level security;
alter table encryption_key_material enable row level security;
alter table encrypted_backups enable row level security;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create policy profiles_select_any_authenticated
  on profiles for select
  to authenticated
  using (true);

create policy profiles_update_self
  on profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy profiles_insert_self
  on profiles for insert
  to authenticated
  with check (id = auth.uid());

-- ---------------------------------------------------------------------------
-- devices
-- ---------------------------------------------------------------------------
create policy devices_select_own
  on devices for select
  to authenticated
  using (user_id = auth.uid());

-- Other users' devices are readable only for their PUBLIC key material,
-- needed to start an X3DH session — never the full row. Exposed via the
-- security-definer function below rather than a broad select policy.
create policy devices_insert_own
  on devices for insert
  to authenticated
  with check (user_id = auth.uid());

create policy devices_update_own_or_service
  on devices for update
  to authenticated
  using (user_id = auth.uid());

-- Device discovery: any authenticated user may look up which ACTIVE
-- device ids another user has, so the client can then fetch each one's
-- prekey bundle below. Ids only — no key material here, kept out of the
-- broad `profiles`-style select on purpose.
create or replace function public.list_user_device_ids(target_user_id uuid)
returns table (device_id uuid, platform text)
language sql
security definer
set search_path = public
as $$
  select d.id, d.platform
  from devices d
  where d.user_id = target_user_id
    and d.revoked_at is null;
$$;

-- Public-safe view: identity/prekey material only, for any authenticated
-- user establishing a session with someone else's device.
create or replace function public.get_device_prekey_bundle(target_device_id uuid)
returns table (
  device_id uuid,
  identity_public_key bytea,
  signed_prekey bytea,
  signed_prekey_signature bytea,
  registration_id integer
)
language sql
security definer
set search_path = public
as $$
  select d.id, d.identity_public_key, d.signed_prekey, d.signed_prekey_signature, d.registration_id
  from devices d
  where d.id = target_device_id
    and d.revoked_at is null;
$$;

-- ---------------------------------------------------------------------------
-- one_time_prekeys — consumed atomically via this RPC, never a raw update
-- from the client, to prevent a race that reuses the same key twice.
-- ---------------------------------------------------------------------------
create policy otp_select_own
  on one_time_prekeys for select
  to authenticated
  using (device_id in (select id from devices where user_id = auth.uid()));

create policy otp_insert_own
  on one_time_prekeys for insert
  to authenticated
  with check (device_id in (select id from devices where user_id = auth.uid()));

create or replace function public.consume_one_time_prekey(target_device_id uuid)
returns table (key_id integer, public_key bytea)
language plpgsql
security definer
set search_path = public
as $$
declare
  consumed_row one_time_prekeys%rowtype;
begin
  select * into consumed_row
  from one_time_prekeys
  where device_id = target_device_id and consumed_at is null
  order by id
  limit 1
  for update skip locked;

  if consumed_row.id is null then
    return; -- caller falls back to X3DH without a one-time prekey
  end if;

  update one_time_prekeys
  set consumed_at = now()
  where id = consumed_row.id;

  return query select consumed_row.key_id, consumed_row.public_key;
end;
$$;

-- ---------------------------------------------------------------------------
-- conversations / conversation_members
-- ---------------------------------------------------------------------------
create policy conversations_select_member
  on conversations for select
  to authenticated
  using (
    exists (
      select 1 from conversation_members cm
      where cm.conversation_id = id and cm.user_id = auth.uid()
    )
  );

create policy conversations_insert_creator
  on conversations for insert
  to authenticated
  with check (created_by = auth.uid());

create policy conversation_members_select_member
  on conversation_members for select
  to authenticated
  using (
    exists (
      select 1 from conversation_members cm2
      where cm2.conversation_id = conversation_members.conversation_id
        and cm2.user_id = auth.uid()
    )
  );

create policy conversation_members_insert_member
  on conversation_members for insert
  to authenticated
  with check (
    user_id = auth.uid()
    or exists (
      select 1 from conversation_members cm3
      where cm3.conversation_id = conversation_members.conversation_id
        and cm3.user_id = auth.uid()
        and cm3.role in ('owner', 'admin')
    )
  );

create policy conversation_members_update_self
  on conversation_members for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- messages
-- ---------------------------------------------------------------------------
create policy messages_select_member
  on messages for select
  to authenticated
  using (
    exists (
      select 1 from conversation_members cm
      where cm.conversation_id = messages.conversation_id and cm.user_id = auth.uid()
    )
  );

create policy messages_insert_member_sender
  on messages for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from conversation_members cm
      where cm.conversation_id = messages.conversation_id and cm.user_id = auth.uid()
    )
  );

create policy messages_update_own
  on messages for update
  to authenticated
  using (sender_id = auth.uid())
  with check (sender_id = auth.uid());

-- ---------------------------------------------------------------------------
-- message_attachments / message_reactions / read_receipts / pinned_messages
-- (all inherit conversation membership via a join to messages)
-- ---------------------------------------------------------------------------
create policy attachments_select_member
  on message_attachments for select
  to authenticated
  using (
    exists (
      select 1 from messages m
      join conversation_members cm on cm.conversation_id = m.conversation_id
      where m.id = message_attachments.message_id and cm.user_id = auth.uid()
    )
  );

create policy attachments_insert_own_message
  on message_attachments for insert
  to authenticated
  with check (
    exists (
      select 1 from messages m
      where m.id = message_attachments.message_id and m.sender_id = auth.uid()
    )
  );

create policy reactions_select_member
  on message_reactions for select
  to authenticated
  using (
    exists (
      select 1 from messages m
      join conversation_members cm on cm.conversation_id = m.conversation_id
      where m.id = message_reactions.message_id and cm.user_id = auth.uid()
    )
  );

create policy reactions_write_own
  on message_reactions for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy receipts_select_member
  on read_receipts for select
  to authenticated
  using (
    exists (
      select 1 from messages m
      join conversation_members cm on cm.conversation_id = m.conversation_id
      where m.id = read_receipts.message_id and cm.user_id = auth.uid()
    )
  );

create policy receipts_write_own
  on read_receipts for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy pinned_select_member
  on pinned_messages for select
  to authenticated
  using (
    exists (
      select 1 from conversation_members cm
      where cm.conversation_id = pinned_messages.conversation_id and cm.user_id = auth.uid()
    )
  );

create policy pinned_write_member
  on pinned_messages for all
  to authenticated
  using (
    exists (
      select 1 from conversation_members cm
      where cm.conversation_id = pinned_messages.conversation_id and cm.user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- blocked_users — a user can never see who has blocked *them*
-- ---------------------------------------------------------------------------
create policy blocked_users_own_only
  on blocked_users for all
  to authenticated
  using (blocker_id = auth.uid())
  with check (blocker_id = auth.uid());

-- ---------------------------------------------------------------------------
-- user_reports — write-only from the client; read is moderation-only
-- (service role), so a reported user can't see or tamper with reports.
-- ---------------------------------------------------------------------------
create policy reports_insert_own
  on user_reports for insert
  to authenticated
  with check (reporter_id = auth.uid());

-- No select policy for `authenticated` — reads happen via the service
-- role from a moderation tool / Edge Function only.

-- ---------------------------------------------------------------------------
-- privacy_settings
-- ---------------------------------------------------------------------------
create policy privacy_settings_own
  on privacy_settings for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- encryption_key_material — never readable by any other user
-- ---------------------------------------------------------------------------
create policy key_material_own_device
  on encryption_key_material for all
  to authenticated
  using (device_id in (select id from devices where user_id = auth.uid()))
  with check (device_id in (select id from devices where user_id = auth.uid()));

-- ---------------------------------------------------------------------------
-- encrypted_backups
-- ---------------------------------------------------------------------------
create policy backups_own
  on encrypted_backups for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Storage buckets + policies (Section 7): avatars (public), chat-media
-- (private), encrypted-backups (private). Buckets are created by the
-- inserts below, so `supabase db push` alone provisions everything here —
-- no separate dashboard/CLI bucket-creation step needed.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('chat-media', 'chat-media', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('encrypted-backups', 'encrypted-backups', false)
on conflict (id) do nothing;

create policy avatars_public_read
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy avatars_owner_write
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- chat-media: readable only by a conversation member for the message that
-- attachment belongs to. The object path convention is
-- `{conversation_id}/{message_id}/{attachment_id}`.
create policy chat_media_select_member
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'chat-media'
    and exists (
      select 1 from conversation_members cm
      where cm.conversation_id = (storage.foldername(name))[1]::uuid
        and cm.user_id = auth.uid()
    )
  );

create policy chat_media_insert_member
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'chat-media'
    and exists (
      select 1 from conversation_members cm
      where cm.conversation_id = (storage.foldername(name))[1]::uuid
        and cm.user_id = auth.uid()
    )
  );

create policy backups_owner_only
  on storage.objects for all
  to authenticated
  using (bucket_id = 'encrypted-backups' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'encrypted-backups' and (storage.foldername(name))[1] = auth.uid()::text);
