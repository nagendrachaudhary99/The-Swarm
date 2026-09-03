/// Supabase connection.
///
/// The publishable key is *designed* to ship inside the client — it grants
/// nothing on its own. Every table is behind RLS, `whispers` has no select
/// policy at all, and positions are only ever reachable through the
/// `security definer` RPCs. The secret key must never appear in this file or
/// anywhere else in `lib/`: it bypasses RLS completely.
///
/// Override at build time when you need to:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
class Config {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://bocxxdktggogogsrhhss.supabase.co',
  );

  static const key = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_KjQ34YkOHGCz_wP6aPU7mw_0GHyuhXZ',
  );

  /// During the pilot, let any working mailbox in — you cannot test a campus
  /// app with ten friends if nine of them only have Gmail. Flip this to false
  /// before launch and the .edu/.ac.in gate is back, with no other change.
  static const pilotOpenSignup = bool.fromEnvironment(
    'PILOT_OPEN_SIGNUP',
    defaultValue: true,
  );

  /// Google Maps. Supply at build time — never commit a key:
  ///   flutter run --dart-define=GOOGLE_MAPS_KEY=AIza...
  /// Leave it empty and the app draws its own dark map instead, which costs
  /// nothing and still works offline.
  static const mapsKey = String.fromEnvironment('GOOGLE_MAPS_KEY');
  static bool get hasMaps => mapsKey.isNotEmpty;

  /// Where the pilot campus sits. Used when a device has no GPS fix (desktop,
  /// web, simulator) so the app is still testable.
  static const fallbackLat = 12.9716;
  static const fallbackLon = 77.5946;
}
