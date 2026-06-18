import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_snapshot.dart';

/// Persists the single active game snapshot to disk so a killed/backgrounded
/// app can resume the same board on next launch. Only one game is tracked at a
/// time (the most recent one).
class ActiveGameStore {
  ActiveGameStore._();

  static const String _key = 'active_game_snapshot';

  /// Discard a snapshot older than this — a stale multiplayer match will have
  /// been forfeited server-side anyway.
  static const Duration _maxAge = Duration(hours: 6);

  static Future<void> save(GameSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(snapshot.toJson()));
  }

  /// Returns the saved snapshot for [userId], or null if none / mismatched /
  /// too old / corrupt.
  static Future<GameSnapshot?> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final snapshot = GameSnapshot.fromJson(json);
      if (snapshot.userId != userId) return null;

      final age = DateTime.now().millisecondsSinceEpoch - snapshot.savedAt;
      if (age > _maxAge.inMilliseconds) {
        await clear();
        return null;
      }
      return snapshot;
    } catch (_) {
      await clear();
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
