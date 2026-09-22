import 'package:flutter_test/flutter_test.dart';

import 'package:secure_chat_app/core/utils/sensitive.dart';

void main() {
  group('Sensitive', () {
    test('toString() never includes the wrapped value (Section 15.3)', () {
      const secret = Sensitive('super-secret-token-value');
      expect(secret.toString(), isNot(contains('super-secret-token-value')));
      expect(secret.toString(), 'Sensitive<String>(redacted)');
    });

    test('interpolating into a string does not leak the value either', () {
      const secret = Sensitive('do-not-log-me');
      final logLine = 'token was: $secret';
      expect(logLine, isNot(contains('do-not-log-me')));
    });

    test('reveal returns the original value', () {
      const secret = Sensitive([1, 2, 3]);
      expect(secret.reveal, [1, 2, 3]);
    });

    test('equality compares the wrapped value, not identity', () {
      const a = Sensitive('same');
      const b = Sensitive('same');
      const c = Sensitive('different');
      expect(a, b);
      expect(a, isNot(c));
    });
  });
}
