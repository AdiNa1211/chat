import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:secure_chat_app/app.dart';
import 'package:secure_chat_app/core/di/injection_container.dart';
import 'package:secure_chat_app/core/network/supabase_config.dart';
// Push notifications disabled for now — see the note at the top of
// features/notifications/data/push_token_service.dart. Re-add these two
// imports plus the Firebase init block below to bring it back.
// import 'package:firebase_core/firebase_core.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:flutter/foundation.dart' show kIsWeb;
// import 'package:secure_chat_app/features/notifications/data/push_token_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _configureLogging();

  if (!SupabaseConfig.isConfigured) {
    // Fail loudly rather than silently running against an empty backend —
    // see supabase_config.dart's --dart-define contract.
    throw StateError(
      'SUPABASE_URL / SUPABASE_ANON_KEY are not set. Run with '
      '--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
    );
  }
  await Supabase.initialize(url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey);

  // Content-free push (Section 10) — DISABLED for now (Supabase has no
  // native push delivery of its own; this would otherwise pull in
  // Firebase purely as the FCM transport). Uncomment to bring it back —
  // mobile-only even then, since Web needs its own `firebase_options.dart`
  // via `flutterfire configure` that this project doesn't set up.
  // if (!kIsWeb) {
  //   try {
  //     await Firebase.initializeApp();
  //     FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  //   } catch (e, st) {
  //     developer.log('Firebase init failed — push disabled this run', error: e, stackTrace: st);
  //   }
  // }

  await initDependencies();

  runApp(const SecureChatApp());
}

void _configureLogging() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    developer.log(
      record.message,
      time: record.time,
      level: record.level.value,
      name: record.loggerName,
      error: record.error,
      stackTrace: record.stackTrace,
    );
  });
}
