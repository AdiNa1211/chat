import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:secure_chat_app/core/database/app_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:secure_chat_app/core/crypto/device_id_codec.dart';
import 'package:secure_chat_app/core/crypto/file_crypto_service.dart';
import 'package:secure_chat_app/core/crypto/models/device_prekey_bundle.dart';
import 'package:secure_chat_app/core/crypto/session_manager.dart';
import 'package:secure_chat_app/core/database/daos/message_dao.dart';
import 'package:secure_chat_app/core/error/failures.dart';
import 'package:secure_chat_app/core/error/result.dart';
import 'package:secure_chat_app/core/utils/app_logger.dart';
import 'package:secure_chat_app/core/utils/sensitive.dart';
import 'package:secure_chat_app/features/chat_1to1/data/ciphertext_envelope.dart';
import 'package:secure_chat_app/features/devices_sessions/domain/device_repository.dart';
import 'package:secure_chat_app/features/media_sharing/domain/media_repository.dart';

/// Phase 1 simplification, documented plainly: the wrapped file key,
/// secretstream header, and file metadata are bundled into ONE small JSON
/// payload and encrypted with a single `SessionManager.encrypt` call
/// (`messages.ciphertext`) rather than the spec's stricter split between
/// `messages.ciphertext` and a separately-ratcheted
/// `message_attachments.encrypted_metadata`. This still meets every
/// substantive requirement in Section 9 (the file itself is streamed
/// through libsodium secretstream, the key is never in plaintext outside
/// the two devices, the metadata is encrypted, integrity is checked) — it
/// just advances the Double Ratchet once per file instead of twice. The
/// same encrypted bytes are also stored in
/// `message_attachments.encrypted_metadata` to satisfy that column's
/// NOT NULL constraint without a second, independently-ordered ratchet
/// step. Splitting them for real is a good Phase 2 hardening item.
class SupabaseMediaRepository implements MediaRepository {
  SupabaseMediaRepository({
    required SupabaseClient client,
    required FileCryptoService fileCryptoService,
    required SessionManager sessionManager,
    required DeviceRepository deviceRepository,
    required MessageDao messageDao,
  })  : _client = client,
        _fileCrypto = fileCryptoService,
        _sessionManager = sessionManager,
        _deviceRepository = deviceRepository,
        _messageDao = messageDao;

  final SupabaseClient _client;
  final FileCryptoService _fileCrypto;
  final SessionManager _sessionManager;
  final DeviceRepository _deviceRepository;
  final MessageDao _messageDao;
  final _log = AppLogger.forName('SupabaseMediaRepository');
  static const _uuid = Uuid();

  String get _myUserId => _client.auth.currentUser!.id;

  @override
  Future<Result<void>> sendFile({
    required String conversationId,
    required String otherUserId,
    required File file,
    required String fileName,
    required String mimeType,
    void Function(double fraction)? onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final cipherPath = p.join(tempDir.path, '${_uuid.v4()}.enc');
      final cipherFile = File(cipherPath);
      final totalBytes = await file.length();

      final encryptResult = await _fileCrypto.encryptFile(
        plainFile: file,
        cipherFile: cipherFile,
        onProgress: (done, total) => onProgress?.call(done / total * 0.5), // 0-50%: encrypt
      );
      if (encryptResult case Err(:final failure)) return Err(failure);
      final encrypted = (encryptResult as Ok<FileEncryptionOutput>).value;

      final messageId = _uuid.v4();
      final storagePath = '$conversationId/$messageId/${_uuid.v4()}.enc';

      await _client.storage.from('chat-media').upload(
            storagePath,
            cipherFile,
            fileOptions: const FileOptions(contentType: 'application/octet-stream'),
          );
      onProgress?.call(0.9);
      await cipherFile.delete(); // ciphertext temp copy no longer needed once uploaded

      final deviceIdsResult = await _deviceRepository.listDeviceIdsFor(otherUserId);
      if (deviceIdsResult case Err(:final failure)) return Err(failure);
      final deviceIds =
          (deviceIdsResult as Ok<List<({String deviceId, String platform})>>).value;
      if (deviceIds.isEmpty) {
        return const Err(ServerFailure('This contact has no active devices to message.'));
      }
      final remoteDeviceUuid = deviceIds.first.deviceId;
      final remoteDeviceIntId = deviceUuidToProtocolDeviceId(remoteDeviceUuid);

      final bundleResult = await _deviceRepository.fetchRemotePreKeyBundle(
        remoteUserId: otherUserId,
        remoteDeviceId: remoteDeviceUuid,
      );
      if (bundleResult case Err(:final failure)) return Err(failure);
      await _sessionManager.ensureSession((bundleResult as Ok<RemotePreKeyBundle>).value);

      final metadataJson = jsonEncode({
        'fileKey': base64Encode(encrypted.fileKey.reveal),
        'header': base64Encode(encrypted.header),
        'fileName': fileName,
        'mimeType': mimeType,
        'sizeBytes': totalBytes,
        'contentHash': base64Encode(encrypted.contentHashOfCiphertext),
      });

      final encryptEnvelope = await _sessionManager.encrypt(
        remoteUserId: otherUserId,
        remoteDeviceId: remoteDeviceIntId,
        plaintext: Uint8List.fromList(utf8.encode(metadataJson)),
      );
      if (encryptEnvelope case Err(:final failure)) return Err(failure);
      final wireBytes =
          CiphertextEnvelopeCodec.encode((encryptEnvelope as Ok<EncryptedEnvelope>).value);

      final myDeviceId = await _deviceRepository.currentDeviceId();
      if (myDeviceId == null) {
        return const Err(UnknownFailure('This device is not registered yet.'));
      }

      final insertedMessage = await _client
          .from('messages')
          .insert({
            'id': messageId,
            'conversation_id': conversationId,
            'sender_id': _myUserId,
            'sender_device_id': myDeviceId,
            'ciphertext': wireBytes,
            'message_type': 'media',
            'client_sent_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      await _client.from('message_attachments').insert({
        'id': _uuid.v4(),
        'message_id': messageId,
        'storage_path': storagePath,
        'encrypted_metadata': wireBytes,
        'size_bytes': totalBytes,
        'chunk_count': encrypted.chunkCount,
        'content_hash_ciphertext': encrypted.contentHashOfCiphertext,
      });

      await _messageDao.upsertMessage(LocalMessagesCompanion.insert(
        id: messageId,
        conversationId: conversationId,
        senderId: _myUserId,
        senderDeviceId: myDeviceId,
        content: fileName, // local preview text; the real bytes live in the attachment row
        messageType: 'media',
        clientSentAt: DateTime.parse(insertedMessage['client_sent_at'] as String),
        serverReceivedAt: Value(DateTime.parse(insertedMessage['server_received_at'] as String)),
        deliveryStatus: const Value('sent'),
      ));

      onProgress?.call(1.0);
      return const Ok(null);
    } catch (e, st) {
      _log.error('sendFile failed', e, st);
      return const Err(CryptoFailure('This file could not be sent.'));
    }
  }

  @override
  Future<Result<File>> downloadAndDecrypt({
    required String messageId,
    void Function(double fraction)? onProgress,
  }) async {
    try {
      final attachment = await _messageDao.attachmentForMessage(messageId);
      if (attachment == null) {
        return const Err(ServerFailure('No attachment found for this message.'));
      }
      if (attachment.localCachePath != null && await File(attachment.localCachePath!).exists()) {
        return Ok(File(attachment.localCachePath!));
      }

      final message = await (_messageDao.attachedDatabase.select(
        _messageDao.attachedDatabase.localMessages,
      )..where((t) => t.id.equals(messageId)))
          .getSingle();
      final senderDeviceIntId = deviceUuidToProtocolDeviceId(message.senderDeviceId);

      final metadataRow =
          await _client.from('message_attachments').select().eq('message_id', messageId).single();
      final wireBytes = metadataRow['encrypted_metadata'];
      final envelope = CiphertextEnvelopeCodec.decode(
        wireBytes is String ? base64Decode(wireBytes) : wireBytes as List<int>,
      );

      final decryptResult = await _sessionManager.decrypt(
        remoteUserId: message.senderId,
        remoteDeviceId: senderDeviceIntId,
        envelope: envelope,
      );
      if (decryptResult case Err(:final failure)) return Err(failure);
      final metadataJson = jsonDecode(utf8.decode((decryptResult as Ok<Uint8List>).value))
          as Map<String, dynamic>;

      final fileKey = Sensitive(base64Decode(metadataJson['fileKey'] as String));
      final fileName = metadataJson['fileName'] as String;

      final tempDir = await getTemporaryDirectory();
      final cipherPath = p.join(tempDir.path, '${metadataRow['id']}.enc');
      final bytes = await _client.storage.from('chat-media').download(
            metadataRow['storage_path'] as String,
          );
      await File(cipherPath).writeAsBytes(bytes);
      onProgress?.call(0.6);

      final cacheDir = await getApplicationSupportDirectory();
      final decryptedDir = Directory(p.join(cacheDir.path, 'decrypted_media'));
      if (!await decryptedDir.exists()) await decryptedDir.create(recursive: true);
      final plainPath = p.join(decryptedDir.path, '${metadataRow['id']}_$fileName');

      final decryptResult2 = await _fileCrypto.decryptFile(
        cipherFile: File(cipherPath),
        plainFile: File(plainPath),
        fileKey: fileKey,
        onProgress: (done, total) => onProgress?.call(0.6 + (done / total) * 0.4),
      );
      await File(cipherPath).delete();
      if (decryptResult2 case Err(:final failure)) return Err(failure);

      await _messageDao.upsertAttachment(LocalAttachmentsCompanion.insert(
        id: metadataRow['id'] as String,
        messageId: messageId,
        storagePath: metadataRow['storage_path'] as String,
        fileName: fileName,
        mimeType: metadataJson['mimeType'] as String,
        sizeBytes: metadataJson['sizeBytes'] as int,
        localCachePath: Value(plainPath),
        downloadStatus: const Value('downloaded'),
      ));

      onProgress?.call(1.0);
      return Ok(File(plainPath));
    } catch (e, st) {
      _log.error('downloadAndDecrypt failed', e, st);
      return const Err(CryptoFailure('This file could not be downloaded.'));
    }
  }

  @override
  Future<void> cleanupExpiredCache({Duration maxAge = const Duration(days: 7)}) async {
    final cacheDir = await getApplicationSupportDirectory();
    final decryptedDir = Directory(p.join(cacheDir.path, 'decrypted_media'));
    if (!await decryptedDir.exists()) return;

    final cutoff = DateTime.now().subtract(maxAge);
    await for (final entity in decryptedDir.list()) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      if (stat.modified.isBefore(cutoff)) {
        // Overwrite-then-delete rather than a plain unlink (Section 9.2):
        // best-effort defense against filesystem-level recovery of
        // decrypted plaintext.
        try {
          final length = await entity.length();
          await entity.writeAsBytes(List<int>.filled(length, 0));
        } catch (_) {
          // Best-effort; proceed to delete regardless.
        }
        await entity.delete();
      }
    }
  }
}
