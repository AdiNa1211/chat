import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:secure_chat_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:secure_chat_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:secure_chat_app/features/auth/presentation/screens/login_screen.dart';
import 'package:secure_chat_app/features/auth/presentation/screens/otp_verification_screen.dart';
import 'package:secure_chat_app/features/auth/presentation/screens/profile_setup_screen.dart';
import 'package:secure_chat_app/features/auth/presentation/screens/splash_screen.dart';
import 'package:secure_chat_app/features/chat_1to1/presentation/screens/chat_list_screen.dart';
import 'package:secure_chat_app/features/chat_1to1/presentation/screens/chat_thread_screen.dart';
import 'package:secure_chat_app/features/chat_1to1/presentation/screens/new_chat_screen.dart';

/// Route paths, centralized so screens navigate by constant rather than a
/// hand-typed string. Replaces the AuthState-switch `_AuthGate` this app
/// started with (Section 14) — same linear flow, now real routes.
abstract final class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const otp = '/otp';
  static const profileSetup = '/profile-setup';
  static const chats = '/chats';
  static const newChat = '/chats/new';
  static String chatThread(String conversationId) => '/chats/$conversationId';
}

/// conversationId travels as a path param (shareable/restorable); these two
/// don't need to be, so they ride along as `extra` instead of a re-fetch.
class ChatThreadRouteExtra {
  const ChatThreadRouteExtra({required this.otherUserId, required this.otherUserDisplayName});
  final String otherUserId;
  final String otherUserDisplayName;
}

/// go_router's `refreshListenable` wants a [Listenable]; go_router removed
/// its own stream-to-listenable helper (`GoRouterRefreshStream`) back in
/// v5, so this is the minimal replacement.
class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(Stream<AuthState> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// Builds the app's router, gated on [authBloc]'s state (Section 14's
/// linear auth flow: splash -> login -> otp -> profile -> chats). Caller
/// owns [authBloc] and must call `.dispose()` on the returned router.
GoRouter buildAppRouter(AuthBloc authBloc) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: _AuthRefreshListenable(authBloc.stream),
    redirect: (context, state) => _redirect(authBloc.state, state.matchedLocation),
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, __) => const SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: AppRoutes.otp,
        // Only reachable while AuthOtpPending (enforced by _redirect below),
        // so the identifier is always present on the bloc's current state.
        builder: (_, __) =>
            OtpVerificationScreen(identifier: (authBloc.state as AuthOtpPending).identifier),
      ),
      GoRoute(path: AppRoutes.profileSetup, builder: (_, __) => const ProfileSetupScreen()),
      GoRoute(
        path: AppRoutes.chats,
        builder: (_, __) => const ChatListScreen(),
        routes: [
          GoRoute(path: 'new', builder: (_, __) => const NewChatScreen()),
          GoRoute(
            path: ':conversationId',
            // A raw deep link / web back-forward with no `extra` falls back
            // to the chat list rather than crashing the builder below.
            redirect: (_, state) => state.extra is ChatThreadRouteExtra ? null : AppRoutes.chats,
            builder: (_, state) {
              final extra = state.extra! as ChatThreadRouteExtra;
              return ChatThreadScreen(
                conversationId: state.pathParameters['conversationId']!,
                otherUserId: extra.otherUserId,
                otherUserDisplayName: extra.otherUserDisplayName,
              );
            },
          ),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Route not found: ${state.uri}')),
    ),
  );
}

String? _redirect(AuthState authState, String location) {
  final onAuthFlow =
      location == AppRoutes.login || location == AppRoutes.otp || location == AppRoutes.profileSetup;

  return switch (authState) {
    AuthLoading() => location == AppRoutes.splash ? null : AppRoutes.splash,
    AuthUnauthenticated() => location == AppRoutes.login ? null : AppRoutes.login,
    AuthOtpPending() => location == AppRoutes.otp ? null : AppRoutes.otp,
    AuthNeedsProfile() => location == AppRoutes.profileSetup ? null : AppRoutes.profileSetup,
    // Only steer away from the auth flow/splash; leave any /chats/... alone
    // so a redirect triggered by an unrelated bloc emission doesn't stomp
    // in-app navigation (e.g. mid-conversation).
    AuthAuthenticated() => (onAuthFlow || location == AppRoutes.splash) ? AppRoutes.chats : null,
  };
}
