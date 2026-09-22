import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:secure_chat_app/core/di/injection_container.dart';
import 'package:secure_chat_app/core/router/app_router.dart';
import 'package:secure_chat_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:secure_chat_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:secure_chat_app/features/chat_1to1/data/outbox_sync_service.dart';
// Push notifications disabled for now — see the note at the top of
// features/notifications/data/push_token_service.dart.
// import 'package:secure_chat_app/features/notifications/data/push_token_service.dart';

class SecureChatApp extends StatefulWidget {
  const SecureChatApp({super.key});

  @override
  State<SecureChatApp> createState() => _SecureChatAppState();
}

class _SecureChatAppState extends State<SecureChatApp> {
  late final AuthBloc _authBloc;
  late final GoRouter _router;
  bool _servicesStarted = false;

  @override
  void initState() {
    super.initState();
    // Built manually (not via BlocProvider's `create:`) so the router can
    // read/react to it too — BlocProvider.value below means this class
    // owns closing it, see dispose().
    _authBloc = AuthBloc(
      requestOtp: getIt(),
      verifyOtp: getIt(),
      completeProfile: getIt(),
      signOut: getIt(),
      authRepository: getIt(),
      deviceProvisioningService: getIt(),
    );
    _router = buildAppRouter(_authBloc);
  }

  @override
  void dispose() {
    _router.dispose();
    _authBloc.close();
    super.dispose();
  }

  /// Started once, the first time auth succeeds this app run (Section
  /// 12.2's outbox drain) — never on every rebuild, and never before a
  /// device/session actually exists.
  void _startAuthenticatedServicesOnce() {
    if (_servicesStarted) return;
    _servicesStarted = true;
    getIt<OutboxSyncService>().start();
    // Push notifications disabled for now — re-add once
    // PushTokenService is un-commented in injection_container.dart.
    // getIt<PushTokenService>().start();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuthBloc>.value(
      value: _authBloc,
      child: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthAuthenticated) _startAuthenticatedServicesOnce();
        },
        child: MaterialApp.router(
          title: 'Secure Chat',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
          routerConfig: _router,
        ),
      ),
    );
  }
}
