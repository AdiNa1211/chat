import 'package:logging/logging.dart';

/// The single sanctioned logging entry point (Section 15.3). Nothing else
/// in the codebase should call `print()` or `debugPrint()` directly —
/// `analysis_options.yaml` turns `avoid_print` on to make that a lint error.
///
/// This wrapper does not attempt to scan strings for secrets: that's
/// unreliable. Instead the rule is structural — call sites that touch
/// passwords, OTPs, tokens, keys, or plaintext must be typed as
/// `Sensitive<T>` (see sensitive.dart), which cannot be interpolated into
/// a loggable string without an explicit, greppable `.reveal`.
class AppLogger {
  AppLogger._(this._logger);

  factory AppLogger.forName(String name) => AppLogger._(Logger(name));

  final Logger _logger;

  void debug(String message) => _logger.fine(message);

  void info(String message) => _logger.info(message);

  void warning(String message, [Object? error, StackTrace? stackTrace]) =>
      _logger.warning(message, error, stackTrace);

  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _logger.severe(message, error, stackTrace);
}
