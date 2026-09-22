import 'package:secure_chat_app/core/error/result.dart';
import 'package:secure_chat_app/features/auth/domain/entities/app_user.dart';

enum OtpChannel { email, phone }

abstract interface class AuthRepository {
  /// Requests an OTP be sent (Supabase Auth handles delivery, Section 3) —
  /// the OTP itself is never logged (Section 15.3).
  Future<Result<void>> requestOtp({required String identifier, required OtpChannel channel});

  Future<Result<AppUser>> verifyOtp({
    required String identifier,
    required OtpChannel channel,
    required String code,
  });

  /// Completes profile setup for a first-time user (username/display
  /// name) — separate from `verifyOtp` because a returning user skips it.
  Future<Result<AppUser>> completeProfile({
    required String username,
    required String displayName,
  });

  Future<AppUser?> currentUser();

  Stream<AppUser?> watchAuthState();

  /// Local sign-out (this device only). "Sign out of all devices"
  /// (Section 10.4) is a `DeviceRepository`/Edge Function concern, not
  /// this repository's.
  Future<Result<void>> signOut();
}
