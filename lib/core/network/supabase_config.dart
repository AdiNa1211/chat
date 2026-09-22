/// Supabase project configuration. Values are read from `--dart-define`
/// at build time (`flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`)
/// so no secret or environment-specific value is hard-coded into source
/// control. Only the **anon/publishable** key belongs here — the
/// service-role key must never ship in the Flutter app (Section 5, 15.2).
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
