import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/analytics_config.dart';

/// Thin wrapper over PostHog so the rest of the app never imports the SDK
/// directly and every event name lives in one place. All calls are guarded by
/// [AnalyticsConfig.enabled] (no-op when no key) and by the user's opt-out
/// preference, so they're always safe to call.
class Analytics {
  Analytics._();

  static const String _optOutKey = 'analytics_opt_out';
  static bool _optedOut = false;

  /// Call once at startup (after PostHog setup) to load the saved opt-out state.
  static Future<void> init() async {
    if (!AnalyticsConfig.enabled) return;
    final prefs = await SharedPreferences.getInstance();
    _optedOut = prefs.getBool(_optOutKey) ?? false;
    if (_optedOut) {
      await Posthog().disable();
    }
  }

  static bool get optedOut => _optedOut;

  static bool get _active => AnalyticsConfig.enabled && !_optedOut;

  /// User-facing privacy switch. Persists and toggles ingestion at the SDK.
  static Future<void> setOptOut(bool value) async {
    _optedOut = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_optOutKey, value);
    if (!AnalyticsConfig.enabled) return;
    if (value) {
      await Posthog().disable();
    } else {
      await Posthog().enable();
    }
  }

  /// Tie subsequent events to a known user (Supabase UUID — never email/PII).
  static Future<void> identify(String userId, {bool isGuest = false}) async {
    if (!_active) return;
    await Posthog().identify(
      userId: userId,
      userProperties: {'is_guest': isGuest},
    );
  }

  /// Capture a named event. Null-valued props are dropped (PostHog expects
  /// non-null Object values).
  static Future<void> capture(
    String event, {
    Map<String, Object?>? props,
  }) async {
    if (!_active) return;
    Map<String, Object>? clean;
    if (props != null) {
      clean = {
        for (final e in props.entries)
          if (e.value != null) e.key: e.value!,
      };
    }
    await Posthog().capture(eventName: event, properties: clean);
  }

  /// Clear identity on sign-out so the next user isn't merged into the previous.
  static Future<void> reset() async {
    if (!AnalyticsConfig.enabled) return;
    await Posthog().reset();
  }
}
