import 'package:equatable/equatable.dart';

import 'package:secure_chat_app/features/auth/domain/auth_repository.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AuthStarted extends AuthEvent {
  const AuthStarted();
}

class OtpRequested extends AuthEvent {
  const OtpRequested({required this.identifier, required this.channel});

  final String identifier;
  final OtpChannel channel;

  @override
  List<Object?> get props => [identifier, channel];
}

class OtpSubmitted extends AuthEvent {
  const OtpSubmitted({required this.code});

  final String code;

  @override
  List<Object?> get props => [code];
}

class ProfileSubmitted extends AuthEvent {
  const ProfileSubmitted({required this.username, required this.displayName});

  final String username;
  final String displayName;

  @override
  List<Object?> get props => [username, displayName];
}

class SignOutRequested extends AuthEvent {
  const SignOutRequested();
}
