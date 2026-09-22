import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as pc;
import 'package:sodium_libs/sodium_libs.dart';

import 'package:secure_chat_app/core/error/failures.dart';
import 'package:secure_chat_app/core/error/result.dart';
import 'package:secure_chat_app/core/utils/app_logger.dart';
import 'package:secure_chat_app/core/utils/sensitive.dart';

/// 4 MiB — large enough to keep per-chunk overhead low, small enough that
/// memory use stays flat regardless of file size (Section 9.1).
const int kFileChunkSize = 4 * 1024 * 1024;

class FileEncryptionOutput {
  const FileEncryptionOutput({
    required this.fileKey,
    required this.header,
    required this.contentHashOfCiphertext,
    required this.chunkCount,
  });

  /// The random per-file key (Section 9.1, step 1) — never reused across
  /// files, and only ever handed to the caller so it can be wrapped under
  /// the E2EE session for the message that references this file. Never
  /// written to disk or a log by this service.
  final Sensitive<Uint8List> fileKey;

  /// libsodium secretstream header — required to start decryption;
  /// travels alongside the wrapped file key inside the message ciphertext,
  /// not as a separate plaintext field.
  final Uint8List header;

  /// Hash of the *encrypted* bytes on disk, used as associated data when
  /// wrapping the file key (Section 9.1, step 6) so a recipient can detect
  /// a swapped/corrupted Storage object before decrypting a single chunk.
  final Uint8List contentHashOfCiphertext;

  final int chunkCount;
}

/// Streaming, chunked file encryption using libsodium's
/// `crypto_secretstream_xchacha20poly1305` (Section 9.1) — the primitive
/// this design specifically chose because it authenticates each chunk,
/// binds chunks together (no reordering), and marks the final chunk so
/// truncation is detectable, all with O(chunk size) memory.
///
/// `sodium_libs`'s secretstream API is Stream-transformer based, not an
/// imperative push()/pull() object: `createPushEx`/`createPullEx` return a
/// `StreamTransformer` you `.bind()` to a `Stream<SecretStreamPlainMessage>`
/// / `Stream<SecretStreamCipherMessage>`. The header isn't a separate
/// out-of-band value on the push side — it's emitted as the *first* item
/// of the resulting cipher stream, and must be fed back as the first item
/// of the cipher stream on the pull side (verified against pub.dev's
/// `sodium` API docs for `SecretStream`/`SecretExStreamTransformer`).
class FileCryptoService {
  FileCryptoService(this._sodium);

  final Sodium _sodium;
  final _log = AppLogger.forName('FileCryptoService');

  Future<Result<FileEncryptionOutput>> encryptFile({
    required File plainFile,
    required File cipherFile,
    void Function(int bytesProcessed, int totalBytes)? onProgress,
  }) async {
    try {
      final key = _sodium.crypto.secretStream.keygen();
      final totalBytes = await plainFile.length();
      final hasher = pc.Sha256();
      final hashSink = hasher.newHashSink();

      final output = cipherFile.openWrite();
      var chunkCount = 0;
      Uint8List? header;

      final transformer = _sodium.crypto.secretStream.createPushEx(key);
      final cipherStream = transformer.bind(
        _plainChunks(plainFile, totalBytes, onProgress),
      );

      await for (final cipherMessage in cipherStream) {
        final bytes = cipherMessage.message;
        if (header == null) {
          // First emitted item is the stream header, not an encrypted
          // chunk — still part of what's written to disk, but reported to
          // the caller separately too (Section 9.1).
          header = bytes;
        } else {
          chunkCount++;
        }
        output.add(bytes);
        hashSink.add(bytes);
      }

      await output.close();
      hashSink.close();
      final digest = await hashSink.hash();

      return Ok(
        FileEncryptionOutput(
          fileKey: Sensitive(Uint8List.fromList(key.extractBytes())),
          header: header ?? Uint8List(0),
          contentHashOfCiphertext: Uint8List.fromList(digest.bytes),
          chunkCount: chunkCount,
        ),
      );
    } catch (e, st) {
      _log.error('File encryption failed', e, st);
      return const Err(CryptoFailure('This file could not be encrypted.'));
    }
  }

  /// Reads [plainFile] in [kFileChunkSize] windows and yields each one as a
  /// tagged plaintext message, using a known file length (rather than
  /// buffering/peeking `openRead()`) so exactly one chunk is tagged
  /// `finalPush` — never zero, never two.
  Stream<SecretStreamPlainMessage> _plainChunks(
    File plainFile,
    int totalBytes,
    void Function(int bytesProcessed, int totalBytes)? onProgress,
  ) async* {
    final raf = await plainFile.open();
    try {
      if (totalBytes == 0) {
        onProgress?.call(0, 0);
        // Uint8List(0) isn't a const expression, so this literal can't be const.
        yield SecretStreamPlainMessage(
          Uint8List(0),
          tag: SecretStreamMessageTag.finalPush,
        );
        return;
      }
      var processed = 0;
      while (processed < totalBytes) {
        final remaining = totalBytes - processed;
        final readSize = remaining < kFileChunkSize ? remaining : kFileChunkSize;
        final chunk = Uint8List.fromList(await raf.read(readSize));
        processed += chunk.length;
        onProgress?.call(processed, totalBytes);
        yield SecretStreamPlainMessage(
          chunk,
          tag: processed >= totalBytes
              ? SecretStreamMessageTag.finalPush
              : SecretStreamMessageTag.message,
        );
      }
    } finally {
      await raf.close();
    }
  }

  Future<Result<void>> decryptFile({
    required File cipherFile,
    required File plainFile,
    required Sensitive<Uint8List> fileKey,
    void Function(int bytesProcessed, int totalBytes)? onProgress,
  }) async {
    try {
      final totalCipherBytes = await cipherFile.length();
      final headerBytes = _sodium.crypto.secretStream.headerBytes;
      final aBytes = _sodium.crypto.secretStream.aBytes;

      final raf = await cipherFile.open();
      final header = Uint8List.fromList(await raf.read(headerBytes));
      await raf.close();

      final key = SecureKey.fromList(_sodium, fileKey.reveal);
      final output = plainFile.openWrite();
      var processed = headerBytes;
      var sawFinal = false;

      // `requireFinalized: false` — a truncated stream is handled below as
      // a normal "incomplete/tampered" result, not an uncaught error.
      final transformer =
          _sodium.crypto.secretStream.createPullEx(key, requireFinalized: false);
      final plainStream = transformer.bind(
        _cipherChunks(cipherFile, header, headerBytes, aBytes),
      );

      await for (final plainMessage in plainStream) {
        if (plainMessage.tag == SecretStreamMessageTag.finalPush) sawFinal = true;
        output.add(plainMessage.message);
        processed += plainMessage.message.length + aBytes;
        onProgress?.call(
          processed > totalCipherBytes ? totalCipherBytes : processed,
          totalCipherBytes,
        );
      }

      await output.close();

      if (!sawFinal) {
        // The stream ended without ever seeing a FINAL-tagged chunk —
        // truncation (Section 9.1, point 2). Delete the partial plaintext
        // rather than leaving something that looks complete but isn't.
        if (await plainFile.exists()) await plainFile.delete();
        return const Err(CryptoFailure('This file is incomplete or was tampered with.'));
      }

      return const Ok(null);
    } catch (e, st) {
      // Any MAC/tag failure inside the pull stream throws — treated
      // uniformly as "corrupted or tampered," never partially trusted
      // (Section 18).
      _log.warning('File decryption rejected corrupted/tampered ciphertext', e, st);
      if (await plainFile.exists()) await plainFile.delete();
      return const Err(CryptoFailure('This file could not be decrypted.'));
    }
  }

  /// Yields [header] as the first cipher message (mirroring what the push
  /// side emits), then every ciphertext chunk that follows it on disk.
  /// Every chunk but the last is exactly `kFileChunkSize + aBytes` long —
  /// only the final one may be shorter — so a fixed-size read loop that
  /// stops on a short/empty read finds the chunk boundaries without
  /// needing the original plaintext length.
  Stream<SecretStreamCipherMessage> _cipherChunks(
    File cipherFile,
    Uint8List header,
    int headerBytes,
    int aBytes,
  ) async* {
    yield SecretStreamCipherMessage(header);
    final raf = await cipherFile.open();
    try {
      await raf.setPosition(headerBytes);
      final cipherChunkSize = kFileChunkSize + aBytes;
      while (true) {
        final chunk = await raf.read(cipherChunkSize);
        if (chunk.isEmpty) break;
        yield SecretStreamCipherMessage(Uint8List.fromList(chunk));
      }
    } finally {
      await raf.close();
    }
  }
}
