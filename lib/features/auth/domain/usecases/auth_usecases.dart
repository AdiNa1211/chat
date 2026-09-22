import 'package:secure_chat_app/core/error/result.dart';
import 'package:secure_chat_app/features/auth/domain/auth_repository.dart';
import 'package:secure_chat_app/features/auth/domain/entities/app_user.dart';

/// Kept as thin, individually-testable use cases (Section 4/18) rather
/// than letting the Bloc call `AuthRepository` methods directly — each one
/// is a natural seam for a unit test with a fake repository.
class RequestOtpUseCase {
  RequestOtpUseCase(this._repo);
  final AuthRepository _repo;

  Future<Result<void>> call({required String identifier, required OtpChannel channel}) {
    return _repo.requestOtp(identifier: identifier, channel: channel);
  }
}

class VerifyOtpUseCase {
  VerifyOtpUseCase(this._repo);
  final AuthRepository _repo;

  Future<Result<AppUser>> call({
    required String identifier,
    required OtpChannel channel,
    required String code,
  }) {
    return _repo.verifyOtp(identifier: identifier, channel: channel, code: code);
  }
}

class CompleteProfileUseCase {
  CompleteProfileUseCase(this._repo);
  final AuthRepository _repo;

  Future<Result<AppUser>> call({required String username, required String displayName}) {
    return _repo.completeProfile(username: username, displayName: displayName);
  }
}

class SignOutUseCase {
  SignOutUseCase(this._repo);
  final AuthRepository _repo;

  Future<Result<void>> call() => _repo.signOut();
}
