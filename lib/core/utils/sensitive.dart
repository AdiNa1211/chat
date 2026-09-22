/// Wraps a value that must never reach a log line, crash report, or
/// analytics event: passwords, OTP codes, auth/refresh tokens, encryption
/// keys (identity/session/file), and decrypted message/file plaintext.
///
/// `toString()` is overridden so an accidental `print(token)`,
/// interpolation into a log message, or crash-reporter breadcrumb prints
/// a redacted placeholder instead of the value (Section 15.3 of the spec).
/// This is a structural guard, not a substitute for reviewing call sites —
/// callers still have to unwrap `.reveal` deliberately to use the value.
class Sensitive<T> {
  const Sensitive(this._value);

  final T _value;

  /// Deliberately explicit name: greppable, and never called by accident
  /// the way `.value` might be.
  T get reveal => _value;

  @override
  String toString() => 'Sensitive<${T.toString()}>(redacted)';

  @override
  bool operator ==(Object other) => other is Sensitive<T> && other._value == _value;

  @override
  int get hashCode => Object.hash(runtimeType, _value.hashCode);
}
