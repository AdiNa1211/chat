import 'dart:io';

import 'package:secure_chat_app/core/error/result.dart';

abstract interface class MediaRepository {
  /// Encrypts `file` locally (Section 9.1), uploads the ciphertext to
  /// Supabase Storage, and sends a `media`-type message whose ciphertext
  /// carries the wrapped file key + encrypted metadata. Returns once the
  /// message row exists — upload progress is reported via `onProgress`
  /// while it runs.
  Future<Result<void>> sendFile({
    required String conversationId,
    required String otherUserId,
    required File file,
    required String fileName,
    required String mimeType,
    void Function(double fraction)? onProgress,
  });

  /// Downloads + decrypts an attachment into the app's private cache
  /// (Section 9.2), returning the local plaintext file path. Idempotent —
  /// returns the existing cached copy if still present.
  Future<Result<File>> downloadAndDecrypt({
    required String messageId,
    void Function(double fraction)? onProgress,
  });

  /// Deletes every locally cached decrypted file older than [maxAge]
  /// (Section 9.2's automatic cleanup) — call on app start and
  /// periodically, not just on thread close.
  Future<void> cleanupExpiredCache({Duration maxAge = const Duration(days: 7)});
}
