import 'package:flutter_test/flutter_test.dart';

import 'package:secure_chat_app/core/error/failures.dart';
import 'package:secure_chat_app/core/error/result.dart';

void main() {
  group('Result', () {
    test('Ok reports isOk/isErr correctly and fold calls onSuccess', () {
      const result = Ok<int>(42);
      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      final folded = result.fold((f) => 'err: ${f.message}', (v) => 'ok: $v');
      expect(folded, 'ok: 42');
    });

    test('Err reports isOk/isErr correctly and fold calls onFailure', () {
      const result = Err<int>(ServerFailure('boom'));
      expect(result.isOk, isFalse);
      expect(result.isErr, isTrue);
      final folded = result.fold((f) => 'err: ${f.message}', (v) => 'ok: $v');
      expect(folded, 'err: boom');
    });

    test('pattern matching destructures Ok/Err (the style used app-wide)', () {
      const Result<int> ok = Ok(7);
      const Result<int> err = Err(UnknownFailure());

      final okOut = switch (ok) {
        Ok(:final value) => value,
        Err() => -1,
      };
      final errOut = switch (err) {
        Ok(:final value) => value,
        Err() => -1,
      };

      expect(okOut, 7);
      expect(errOut, -1);
    });
  });
}
