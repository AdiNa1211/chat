import 'package:equatable/equatable.dart';

enum AttachmentDownloadStatus { notDownloaded, downloading, downloaded, failed }

class Attachment extends Equatable {
  const Attachment({
    required this.id,
    required this.messageId,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.downloadStatus,
    this.localCachePath,
  });

  final String id;
  final String messageId;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String? localCachePath;
  final AttachmentDownloadStatus downloadStatus;

  @override
  List<Object?> get props =>
      [id, messageId, fileName, mimeType, sizeBytes, localCachePath, downloadStatus];
}
