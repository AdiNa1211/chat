import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:secure_chat_app/core/error/result.dart';
import 'package:secure_chat_app/features/auth/domain/auth_repository.dart';
import 'package:secure_chat_app/features/auth/domain/entities/app_user.dart';
import 'package:secure_chat_app/features/auth/domain/usecases/auth_usecases.dart';
import 'package:secure_chat_app/features/auth/presentation/bloc/auth_event.dart';
import 'package:secure_chat_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:secure_chat_app/features/devices_sessions/domain/device_provisioning_service.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({
    required RequestOtpUseCase requestOtp,
    required VerifyOtpUseCase verifyOtp,
    required CompleteProfileUseCase completeProfile,
    required SignOutUseCase signOut,
    required AuthRepository authRepository,
    required DeviceProvisioningService deviceProvisioningService,
  })  : _requestOtp = requestOtp,
        _verifyOtp = verifyOtp,
        _completeProfile = completeProfile,
        _signOut = signOut,
        _authRepository = authRepository,
        _deviceProvisioningService = deviceProvisioningService,
        super(const AuthLoading()) {
    on<AuthStarted>(_onStarted);
    on<OtpRequested>(_onOtpRequested);
    on<OtpSubmitted>(_onOtpSubmitted);
    on<ProfileSubmitted>(_onProfileSubmitted);
    on<SignOutRequested>(_onSignOutRequested);
  }

  final RequestOtpUseCase _requestOtp;
  final VerifyOtpUseCase _verifyOtp;
  final CompleteProfileUseCase _completeProfile;
  final SignOutUseCase _signOut;
  final AuthRepository _authRepository;
  final DeviceProvisioningService _deviceProvisioningService;

  // Held only in memory between "OTP requested" and "OTP submitted" —
  // never persisted.
  String? _pendingIdentifier;
  OtpChannel? _pendingChannel;

  Future<void> _onStarted(AuthStarted event, Emitter<AuthState> emit) async {
    final user = await _authRepository.currentUser();
    if (user == null) {
      emit(const AuthUnauthenticated());
      return;
    }
    await _ensureDeviceProvisioned(emit, user);
  }

  Future<void> _onOtpRequested(OtpRequested event, Emitter<AuthState> emit) async {
    _pendingIdentifier = event.identifier;
    _pendingChannel = event.channel;
    final result = await _requestOtp(identifier: event.identifier, channel: event.channel);
    result.fold(
      (failure) => emit(AuthUnauthenticated(errorMessage: failure.message)),
      (_) => emit(AuthOtpPending(identifier: event.identifier, channel: event.channel)),
    );
  }

  Future<void> _onOtpSubmitted(OtpSubmitted event, Emitter<AuthState> emit) async {
    final identifier = _pendingIdentifier;
    final channel = _pendingChannel;
    if (identifier == null || channel == null) {
      emit(const AuthUnauthenticated(errorMessage: 'Request a code first.'));
      return;
    }

    emit(AuthOtpPending(identifier: identifier, channel: channel, isSubmitting: true));
    final result = await _verifyOtp(identifier: identifier, channel: channel, code: event.code);

    switch (result) {
      case Err(:final failure):
        emit(AuthOtpPending(identifier: identifier, channel: channel, errorMessage: failure.message));
      case Ok(:final value):
        if (value.username.isEmpty) {
          emit(const AuthNeedsProfile());
        } else {
          await _ensureDeviceProvisioned(emit, value);
        }
    }
  }

  Future<void> _onProfileSubmitted(ProfileSubmitted event, Emitter<AuthState> emit) async {
    final result = await _completeProfile(username: event.username, displayName: event.displayName);
    switch (result) {
      case Err(:final failure):
        emit(AuthNeedsProfile(errorMessage: failure.message));
      case Ok(:final value):
        await _ensureDeviceProvisioned(emit, value);
    }
  }

  Future<void> _onSignOutRequested(SignOutRequested event, Emitter<AuthState> emit) async {
    await _signOut();
    _pendingIdentifier = null;
    _pendingChannel = null;
    emit(const AuthUnauthenticated());
  }

  /// This is where Phase 1's "Device/Identity Keys" step (Section 2.1)
  /// actually runs: right after auth succeeds, before the user reaches
  /// the chat list, so a device is never left able to sign in but unable
  /// to establish E2EE sessions.
  Future<void> _ensureDeviceProvisioned(Emitter<AuthState> emit, AppUser user) async {
    final deviceName = await _defaultDeviceName();
    final provisionResult =
        await _deviceProvisioningService.provisionThisDeviceIfNeeded(deviceName: deviceName);

    if (provisionResult case Err(:final failure)) {
      // Auth succeeded but device provisioning failed (e.g. offline) —
      // surface distinctly rather than silently landing the user in a
      // chat list that can't actually send anything encrypted yet.
      emit(AuthUnauthenticated(
        errorMessage:
            'Signed in, but this device could not be set up for secure messaging: '
            '${failure.message}. Pull to retry once online.',
      ));
      return;
    }

    emit(AuthAuthenticated(user));
  }

  Future<String> _defaultDeviceName() async {
    try {
      if (Platform.isAndroid) return 'Android device';
      if (Platform.isIOS) return 'iPhone';
      return 'Web browser';
    } catch (_) {
      return 'This device';
    }
  }
}
