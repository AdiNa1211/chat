import 'package:equatable/equatable.dart';

import 'package:secure_chat_app/features/auth/domain/auth_repository.dart';
import 'package:secure_chat_app/features/auth/domain/entities/app_user.dart';

sealed class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

/// Splash: still checking whether a session already exists.
class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({this.errorMessage});
  final String? errorMessage;

  @override
  List<Object?> get props => [errorMessage];
}

class AuthOtpPending extends AuthState {
  const AuthOtpPending({
    required this.identifier,
    required this.channel,
    this.errorMessage,
    this.isSubmitting = false,
  });

  final String identifier;
  final OtpChannel channel;
  final String? errorMessage;
  final bool isSubmitting;

  @override
  List<Object?> get props => [identifier, channel, errorMessage, isSubmitting];
}

/// Verified, but no profile yet — route to profile setup.
class AuthNeedsProfile extends AuthState {
  const AuthNeedsProfile({this.errorMessage});
  final String? errorMessage;

  @override
  List<Object?> get props => [errorMessage];
}

/// Fully authenticated and this device's E2EE identity is provisioned.
class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);
  final AppUser user;

  @override
  List<Object?> get props => [user];
}
