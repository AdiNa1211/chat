// `supabase_flutter` re-exports gotrue's own `OtpChannel` (used for its
// `signInWithOtp(channel: ...)` param, which this app doesn't use) — hidden
// here so it doesn't collide with this app's own `OtpChannel` below.
import 'package:supabase_flutter/supabase_flutter.dart' hide OtpChannel;

import 'package:secure_chat_app/core/error/failures.dart';
import 'package:secure_chat_app/core/error/result.dart';
import 'package:secure_chat_app/core/utils/app_logger.dart';
import 'package:secure_chat_app/features/auth/domain/auth_repository.dart';
import 'package:secure_chat_app/features/auth/domain/entities/app_user.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;
  final _log = AppLogger.forName('SupabaseAuthRepository');

  @override
  Future<Result<void>> requestOtp({
    required String identifier,
    required OtpChannel channel,
  }) async {
    try {
      if (channel == OtpChannel.email) {
        await _client.auth.signInWithOtp(email: identifier);
      } else {
        await _client.auth.signInWithOtp(phone: identifier);
      }
      // Deliberately not logging `identifier` at info level with any
      // request id that could double as a trackable OTP correlation —
      // Section 15.3 errs on the side of logging nothing here at all.
      return const Ok(null);
    } on AuthException catch (e) {
      return Err(AuthFailure(e.message));
    } catch (e, st) {
      _log.error('requestOtp failed', e, st);
      return const Err(UnknownFailure());
    }
  }

  @override
  Future<Result<AppUser>> verifyOtp({
    required String identifier,
    required OtpChannel channel,
    required String code,
  }) async {
    try {
      final response = channel == OtpChannel.email
          ? await _client.auth.verifyOTP(
              type: OtpType.email,
              email: identifier,
              token: code,
            )
          : await _client.auth.verifyOTP(
              type: OtpType.sms,
              phone: identifier,
              token: code,
            );

      final user = response.user;
      if (user == null) return const Err(AuthFailure('Verification failed.'));

      final profile = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null) {
        // First-time user — profile row is created explicitly in
        // `completeProfile` once they pick a username, not implicitly
        // here, so the UI can route to profile setup.
        return Ok(AppUser(id: user.id, username: '', displayName: ''));
      }

      return Ok(_userFromRow(profile));
    } on AuthException catch (e) {
      return Err(AuthFailure(e.message));
    } catch (e, st) {
      _log.error('verifyOtp failed', e, st);
      return const Err(UnknownFailure());
    }
  }

  @override
  Future<Result<AppUser>> completeProfile({
    required String username,
    required String displayName,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return const Err(AuthFailure('Not signed in.'));

      await _client.from('profiles').upsert({
        'id': userId,
        'username': username,
        'display_name': displayName,
      });
      await _client.from('privacy_settings').upsert({'user_id': userId});

      return Ok(AppUser(id: userId, username: username, displayName: displayName));
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        return const Err(ValidationFailure('That username is already taken.'));
      }
      return Err(ServerFailure(e.message));
    } catch (e, st) {
      _log.error('completeProfile failed', e, st);
      return const Err(UnknownFailure());
    }
  }

  @override
  Future<AppUser?> currentUser() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final profile = await _client.from('profiles').select().eq('id', user.id).maybeSingle();
    if (profile == null) return null;
    return _userFromRow(profile);
  }

  @override
  Stream<AppUser?> watchAuthState() {
    return _client.auth.onAuthStateChange.asyncMap((event) async {
      final user = event.session?.user;
      if (user == null) return null;
      final profile = await _client.from('profiles').select().eq('id', user.id).maybeSingle();
      return profile == null ? null : _userFromRow(profile);
    });
  }

  @override
  Future<Result<void>> signOut() async {
    try {
      await _client.auth.signOut();
      return const Ok(null);
    } catch (e, st) {
      _log.error('signOut failed', e, st);
      return const Err(UnknownFailure());
    }
  }

  AppUser _userFromRow(Map<String, dynamic> row) {
    return AppUser(
      id: row['id'] as String,
      username: row['username'] as String,
      displayName: row['display_name'] as String,
      avatarUrl: row['avatar_url'] as String?,
    );
  }
}
