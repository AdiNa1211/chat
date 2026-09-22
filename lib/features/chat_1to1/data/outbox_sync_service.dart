import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:secure_chat_app/core/utils/app_logger.dart';
import 'package:secure_chat_app/features/chat_1to1/domain/chat_repository.dart';

/// Drives Section 12.2/12.3: drains the offline outbox as soon as
/// connectivity returns, and on a slow periodic timer while online (to
/// catch anything that failed mid-send for a reason other than "offline",
/// e.g. a transient server error). Start once at app launch, alongside
/// auth — not per-screen, since sends can be queued from a thread that's
/// no longer open.
class OutboxSyncService {
  OutboxSyncService(this._chatRepository, {Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final ChatRepository _chatRepository;
  final Connectivity _connectivity;
  final _log = AppLogger.forName('OutboxSyncService');

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _periodicTimer;
  bool _draining = false;

  void start() {
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline) {
        _log.info('Connectivity restored — draining outbox.');
        unawaited(_drainSafely());
      }
    });

    _periodicTimer = Timer.periodic(const Duration(seconds: 30), (_) => _drainSafely());

    // Also attempt once at startup, in case messages were queued while
    // the app was closed.
    unawaited(_drainSafely());
  }

  Future<void> _drainSafely() async {
    if (_draining) return; // avoid overlapping drains from timer + connectivity events
    _draining = true;
    try {
      await _chatRepository.drainOutbox();
    } catch (e, st) {
      _log.error('drainOutbox failed', e, st);
    } finally {
      _draining = false;
    }
  }

  void dispose() {
    _connectivitySub?.cancel();
    _periodicTimer?.cancel();
  }
}
