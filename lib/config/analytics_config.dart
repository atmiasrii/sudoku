/// PostHog analytics configuration. The project token is publishable (a
/// write-only ingest key, safe to ship), but we read it from --dart-define so
/// it isn't hardcoded and analytics simply no-ops when unset (dev/CI/tests).
///
/// Run with:
///   flutter run --dart-define=POSTHOG_KEY=phc_xxx \
///     --dart-define=POSTHOG_HOST=https://us.i.posthog.com
class AnalyticsConfig {
  AnalyticsConfig._();

  static const String key = String.fromEnvironment('POSTHOG_KEY');

  static const String host = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://us.i.posthog.com',
  );

  /// Analytics is active only when a project key was provided at build time.
  static bool get enabled => key.isNotEmpty;
}
