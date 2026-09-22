import 'dart:io' show Platform;

import 'package:secure_chat_app/core/crypto/identity_key_service.dart';
import 'package:secure_chat_app/core/error/result.dart';
import 'package:secure_chat_app/core/utils/app_logger.dart';
import 'package:secure_chat_app/features/devices_sessions/domain/device_repository.dart';

/// Orchestrates "Device/Identity Keys" (Section 2.1's Phase 1 sub-order,
/// step 2): generate this device's Signal Protocol key material locally,
/// then publish only the public halves to Supabase. Called once, right
/// after a successful auth (Section 8.2) — kept out of `AuthBloc` itself
/// so the auth feature doesn't need to know about crypto internals.
class DeviceProvisioningService {
  DeviceProvisioningService(this._identityKeyService, this._deviceRepository);

  final IdentityKeyService _identityKeyService;
  final DeviceRepository _deviceRepository;
  final _log = AppLogger.forName('DeviceProvisioningService');

  Future<Result<void>> provisionThisDeviceIfNeeded({required String deviceName}) async {
    final existingDeviceId = await _deviceRepository.currentDeviceId();
    if (existingDeviceId != null) {
      _log.info('Device already registered server-side ($existingDeviceId).');
      return const Ok(null);
    }

    final provisioned = await _identityKeyService.provisionDeviceIfNeeded();
    final platform = _currentPlatformLabel();

    final registerResult = await _deviceRepository.registerDevice(
      deviceName: deviceName,
      platform: platform,
      bundle: provisioned.bundle,
      oneTimePreKeys: provisioned.oneTimePreKeys,
    );

    if (registerResult is Err<String>) {
      return Err(registerResult.failure);
    }

    _log.info('Device provisioned and registered.');
    return const Ok(null);
  }

  String _currentPlatformLabel() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'web';
  }
}
