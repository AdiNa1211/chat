import 'package:get_it/get_it.dart';
import 'package:sodium_libs/sodium_libs.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:secure_chat_app/core/crypto/file_crypto_service.dart';
import 'package:secure_chat_app/core/crypto/identity_key_service.dart';
import 'package:secure_chat_app/core/crypto/secure_key_storage.dart';
import 'package:secure_chat_app/core/crypto/session_manager.dart';
import 'package:secure_chat_app/core/crypto/signal_store_adapter.dart';
import 'package:secure_chat_app/core/database/app_database.dart';
import 'package:secure_chat_app/core/network/realtime_channel_manager.dart';
import 'package:secure_chat_app/features/auth/data/supabase_auth_repository.dart';
import 'package:secure_chat_app/features/auth/domain/auth_repository.dart';
import 'package:secure_chat_app/features/auth/domain/usecases/auth_usecases.dart';
import 'package:secure_chat_app/features/chat_1to1/data/chat_repository_impl.dart';
import 'package:secure_chat_app/features/chat_1to1/data/outbox_sync_service.dart';
import 'package:secure_chat_app/features/chat_1to1/domain/chat_repository.dart';
import 'package:secure_chat_app/features/devices_sessions/data/supabase_device_repository.dart';
import 'package:secure_chat_app/features/devices_sessions/domain/device_provisioning_service.dart';
import 'package:secure_chat_app/features/devices_sessions/domain/device_repository.dart';
import 'package:secure_chat_app/features/media_sharing/data/supabase_media_repository.dart';
import 'package:secure_chat_app/features/media_sharing/domain/media_repository.dart';
// Push notifications are disabled for now — see the note at the top of
// features/notifications/data/push_token_service.dart. Re-add these two
// imports (and the registrations at the bottom of this file) to bring it
// back.
// import 'package:secure_chat_app/features/notifications/data/local_notification_service.dart';
// import 'package:secure_chat_app/features/notifications/data/push_token_service.dart';

/// The app's single service locator. Screens/cubits/blocs resolve
/// repositories and cross-cutting services via `getIt<T>()`; the Blocs and
/// per-screen Cubits themselves are constructed where they're provided
/// (`app.dart` for `AuthBloc`/`ChatListCubit`, each screen's own
/// `BlocProvider` for `ChatThreadCubit`) rather than registered here —
/// see chat_thread_screen.dart for that pattern.
final getIt = GetIt.instance;

/// Wires every dependency below. Call once, after `Supabase.initialize(...)`
/// (Section 2's Phase 0 "Foundation" step) and before `runApp`. Guarded so
/// a Flutter hot-restart in debug mode — which re-runs `main()` but not
/// process state — doesn't try to double-register everything.
Future<void> initDependencies() async {
  if (getIt.isRegistered<SupabaseClient>()) return;

  // -- External singletons ---------------------------------------------------
  final supabaseClient = Supabase.instance.client;
  getIt.registerSingleton<SupabaseClient>(supabaseClient);

  // NOTE: `sodium_libs`'s exact init entrypoint name/shape for the pinned
  // v3 release should be confirmed via `flutter analyze` — see the same
  // pub.dev-unreachable-from-sandbox caveat on FileCryptoService.
  final sodium = await SodiumInit.init();
  getIt.registerSingleton<Sodium>(sodium);

  // -- Local encrypted database (Section 3) -----------------------------------
  final secureKeyStorage = SecureKeyStorage();
  getIt.registerSingleton<SecureKeyStorage>(secureKeyStorage);

  final dbPassphrase = await secureKeyStorage.getOrCreateDatabasePassphrase();
  final appDatabase = AppDatabase.open(sqlCipherPassphrase: dbPassphrase.reveal);
  getIt.registerSingleton<AppDatabase>(appDatabase);

  // -- Crypto (Section 8) ------------------------------------------------------
  final signalStoreAdapter = SignalStoreAdapter(appDatabase.signalStoreDao);
  getIt.registerSingleton<SignalStoreAdapter>(signalStoreAdapter);
  getIt.registerSingleton<IdentityKeyService>(IdentityKeyService(signalStoreAdapter));
  getIt.registerSingleton<SessionManager>(SessionManager(signalStoreAdapter));
  getIt.registerSingleton<FileCryptoService>(FileCryptoService(sodium));

  // -- Realtime -----------------------------------------------------------
  getIt.registerSingleton<RealtimeChannelManager>(RealtimeChannelManager(supabaseClient));

  // -- Devices/sessions (Section 5/8.2) --------------------------------------
  getIt.registerSingleton<DeviceRepository>(
    SupabaseDeviceRepository(supabaseClient, secureKeyStorage),
  );
  getIt.registerSingleton<DeviceProvisioningService>(
    DeviceProvisioningService(getIt<IdentityKeyService>(), getIt<DeviceRepository>()),
  );

  // -- Auth ---------------------------------------------------------------
  getIt.registerSingleton<AuthRepository>(SupabaseAuthRepository(supabaseClient));
  getIt.registerFactory<RequestOtpUseCase>(() => RequestOtpUseCase(getIt<AuthRepository>()));
  getIt.registerFactory<VerifyOtpUseCase>(() => VerifyOtpUseCase(getIt<AuthRepository>()));
  getIt.registerFactory<CompleteProfileUseCase>(
      () => CompleteProfileUseCase(getIt<AuthRepository>()));
  getIt.registerFactory<SignOutUseCase>(() => SignOutUseCase(getIt<AuthRepository>()));

  // -- 1:1 chat (Section 8/9/12) ------------------------------------------
  getIt.registerSingleton<ChatRepository>(
    ChatRepositoryImpl(
      client: supabaseClient,
      conversationDao: appDatabase.conversationDao,
      messageDao: appDatabase.messageDao,
      outboxDao: appDatabase.outboxDao,
      sessionManager: getIt<SessionManager>(),
      deviceRepository: getIt<DeviceRepository>(),
      realtimeChannelManager: getIt<RealtimeChannelManager>(),
    ),
  );
  getIt.registerSingleton<OutboxSyncService>(OutboxSyncService(getIt<ChatRepository>()));

  // -- Encrypted media (Section 9) ------------------------------------------
  getIt.registerSingleton<MediaRepository>(
    SupabaseMediaRepository(
      client: supabaseClient,
      fileCryptoService: getIt<FileCryptoService>(),
      sessionManager: getIt<SessionManager>(),
      deviceRepository: getIt<DeviceRepository>(),
      messageDao: appDatabase.messageDao,
    ),
  );

  // -- Content-free push (Section 10) — DISABLED for now ---------------------
  // final localNotifications = LocalNotificationService();
  // getIt.registerSingleton<LocalNotificationService>(localNotifications);
  // getIt.registerSingleton<PushTokenService>(
  //   PushTokenService(getIt<DeviceRepository>(), localNotifications),
  // );
}
