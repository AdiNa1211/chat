/// Base type for all domain-level failures. Repositories return
/// `Result<T>` (see result.dart) rather than throwing, so the
/// presentation layer never has to guess what can go wrong.
sealed class Failure {
  const Failure(this.message);

  final String message;
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No network connection.']);
}

class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

/// Session/device was revoked (Section 10.4 / 15.2 of the spec) — the UI
/// must force a re-authentication, never silently retry.
class SessionRevokedFailure extends Failure {
  const SessionRevokedFailure([
    super.message = 'This device was signed out remotely.',
  ]);
}

class ServerFailure extends Failure {
  const ServerFailure(super.message);
}

/// Thrown by the crypto layer. Deliberately generic in its user-facing
/// message — never leaks *why* decryption failed (wrong key vs. corrupted
/// ciphertext vs. replay) to anything that isn't the crypto layer itself,
/// since that distinction can be a side channel.
class CryptoFailure extends Failure {
  const CryptoFailure([super.message = 'This message could not be decrypted.']);
}

class StorageFailure extends Failure {
  const StorageFailure(super.message);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'Something went wrong.']);
}
