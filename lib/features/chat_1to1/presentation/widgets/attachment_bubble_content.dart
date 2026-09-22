import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import 'package:secure_chat_app/core/di/injection_container.dart';
import 'package:secure_chat_app/core/error/result.dart';
import 'package:secure_chat_app/features/media_sharing/domain/media_repository.dart';

enum _DownloadState { idle, downloading, ready, failed }

/// Renders a `media`-type message's file chip and drives on-demand
/// decrypt-and-open (Section 9.2) — nothing is decrypted until tapped.
/// Web is disabled here for the same dart:io reason noted on
/// [FileCryptoService]/[SupabaseMediaRepository]: Phase 1 media sharing is
/// mobile/desktop only.
class AttachmentBubbleContent extends StatefulWidget {
  const AttachmentBubbleContent({
    super.key,
    required this.messageId,
    required this.fileName,
    required this.onColor,
  });

  final String messageId;
  final String fileName;
  final Color onColor;

  @override
  State<AttachmentBubbleContent> createState() => _AttachmentBubbleContentState();
}

class _AttachmentBubbleContentState extends State<AttachmentBubbleContent> {
  _DownloadState _state = _DownloadState.idle;
  double _progress = 0;
  File? _localFile;

  Future<void> _handleTap() async {
    if (_state == _DownloadState.downloading) return;
    if (_state == _DownloadState.ready && _localFile != null) {
      await OpenFilex.open(_localFile!.path);
      return;
    }
    setState(() => _state = _DownloadState.downloading);
    final result = await getIt<MediaRepository>().downloadAndDecrypt(
      messageId: widget.messageId,
      onProgress: (fraction) {
        if (mounted) setState(() => _progress = fraction);
      },
    );
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        setState(() {
          _state = _DownloadState.ready;
          _localFile = value;
        });
        await OpenFilex.open(value.path);
      case Err():
        setState(() => _state = _DownloadState.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: kIsWeb ? null : _handleTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_leadingIcon(), color: widget.onColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              widget.fileName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: widget.onColor),
            ),
          ),
          if (_state == _DownloadState.downloading) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: _progress > 0 ? _progress : null,
                color: widget.onColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _leadingIcon() {
    switch (_state) {
      case _DownloadState.ready:
        return Icons.insert_drive_file;
      case _DownloadState.failed:
        return Icons.error_outline;
      case _DownloadState.downloading:
      case _DownloadState.idle:
        return Icons.attach_file;
    }
  }
}
