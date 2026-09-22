// Content-free push (Section 10): fires on every new `messages` row and
// wakes the recipient's devices with a DATA-ONLY FCM message — no
// plaintext, no sender name, no preview, not even server-side. The client
// (flutter local_notification_service.dart) is the only thing that ever
// decides what text a human sees, and it only ever shows a generic
// "New message" string it made up locally.
//
// SETUP (not done by any migration — deliberately, so no secret ever
// lands in versioned SQL):
//   1. `supabase functions deploy push-notify`
//   2. `supabase secrets set PUSH_WEBHOOK_SECRET=<random-string>`
//      `supabase secrets set FCM_SERVER_KEY=<your Firebase Cloud Messaging
//      legacy server key>` (Phase 2 TODO: migrate to the HTTP v1 API with
//      a service-account OAuth token — the legacy key API used here is
//      simpler for Phase 1 but is deprecated upstream)
//   3. In the Supabase Studio: Database -> Webhooks -> create one on
//      `messages` INSERT -> HTTP request to this function's URL, with an
//      `x-webhook-secret: <same random string>` header. This keeps the
//      webhook wiring in the dashboard/CLI rather than a hardcoded-secret
//      migration.

import { createClient } from 'jsr:@supabase/supabase-js@2';

interface MessageRow {
  id: string;
  conversation_id: string;
  sender_id: string;
  message_type: string;
}

interface WebhookPayload {
  type: string;
  table: string;
  record: MessageRow;
}

const FCM_LEGACY_ENDPOINT = 'https://fcm.googleapis.com/fcm/send';

Deno.serve(async (req) => {
  const webhookSecret = Deno.env.get('PUSH_WEBHOOK_SECRET');
  if (!webhookSecret || req.headers.get('x-webhook-secret') !== webhookSecret) {
    return new Response('Unauthorized', { status: 401 });
  }

  const fcmServerKey = Deno.env.get('FCM_SERVER_KEY');
  if (!fcmServerKey) {
    console.error('FCM_SERVER_KEY is not set');
    return new Response('Server misconfigured', { status: 500 });
  }

  let payload: WebhookPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response('Invalid JSON', { status: 400 });
  }

  if (payload.table !== 'messages' || payload.type !== 'INSERT') {
    return new Response('Ignored', { status: 200 });
  }
  const message = payload.record;

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    // Service role: this function runs server-side only, never shipped to
    // a client, and is the one place allowed to see across-user device
    // rows to fan a push out (Section 15.1's "service role never leaves
    // the server" boundary).
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // Recipients: every other member of the conversation, not the sender.
  const { data: members, error: membersError } = await supabase
    .from('conversation_members')
    .select('user_id')
    .eq('conversation_id', message.conversation_id)
    .neq('user_id', message.sender_id);

  if (membersError) {
    console.error('Failed to load conversation members', membersError);
    return new Response('Failed to load recipients', { status: 500 });
  }
  const recipientIds = (members ?? []).map((m) => m.user_id as string);
  if (recipientIds.length === 0) return new Response('No recipients', { status: 200 });

  const { data: devices, error: devicesError } = await supabase
    .from('devices')
    .select('id, push_token')
    .in('user_id', recipientIds)
    .is('revoked_at', null)
    .not('push_token', 'is', null);

  if (devicesError) {
    console.error('Failed to load recipient devices', devicesError);
    return new Response('Failed to load devices', { status: 500 });
  }
  if (!devices || devices.length === 0) return new Response('No push tokens', { status: 200 });

  const staleDeviceIds: string[] = [];

  await Promise.all(
    devices.map(async (device) => {
      const response = await fetch(FCM_LEGACY_ENDPOINT, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `key=${fcmServerKey}`,
        },
        // `data`-only, no `notification` block — see the file header.
        body: JSON.stringify({
          to: device.push_token,
          priority: 'high',
          content_available: true,
          data: {
            type: 'new_message',
            conversation_id: message.conversation_id,
            message_id: message.id,
          },
        }),
      });

      if (response.ok) {
        const result = await response.json();
        const err = result?.results?.[0]?.error;
        if (err === 'NotRegistered' || err === 'InvalidRegistration') {
          staleDeviceIds.push(device.id as string);
        }
      } else {
        console.error(`FCM send failed for device ${device.id}: ${response.status}`);
      }
    }),
  );

  // Best-effort cleanup so a dead token doesn't keep costing an FCM call
  // on every future message.
  if (staleDeviceIds.length > 0) {
    await supabase.from('devices').update({ push_token: null }).in('id', staleDeviceIds);
  }

  return new Response('OK', { status: 200 });
});
