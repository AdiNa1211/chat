import 'package:secure_chat_app/core/error/failures.dart';

/// A minimal `Either`-shaped result so use cases/repositories never throw
/// across a layer boundary. Kept hand-rolled (no `dartz`/`fpdart` codegen
/// dependency) to keep the dependency surface small.
sealed class Result<T> {
  const Result();

  R fold<R>(R Function(Failure failure) onFailure, R Function(T value) onSuccess) {
    final self = this;
    if (self is Ok<T>) return onSuccess(self.value);
    if (self is Err<T>) return onFailure(self.failure);
    throw StateError('Unreachable: Result must be Ok or Err');
  }

  bool get isOk => this is Ok<T>;

  bool get isErr => this is Err<T>;
}

class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;
}

class Err<T> extends Result<T> {
  const Err(this.failure);

  final Failure failure;
}
