import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ProfileCacheEntry {
  final int rating;
  final int ratingDelta;
  final int winStreak;
  final List<Map<String, dynamic>> matchHistory;

  ProfileCacheEntry({
    required this.rating,
    required this.ratingDelta,
    required this.winStreak,
    required this.matchHistory,
  });
}

/// Persists the last-known rating/history snapshot so HomeScreen can render
/// instantly on mount instead of blocking on a network round-trip. Always
/// superseded by the next successful profile fetch — no max-age eviction.
class ProfileCacheStore {
  ProfileCacheStore._();

  static const String _key = 'profile_cache';

  static Future<void> save({
    required String userId,
    required int rating,
    required int ratingDelta,
    required int winStreak,
    required List<Map<String, dynamic>> matchHistory,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'userId': userId,
        'rating': rating,
        'ratingDelta': ratingDelta,
        'winStreak': winStreak,
        'matchHistory': matchHistory,
      }),
    );
  }

  /// Returns the cached profile for [userId], or null if none / mismatched /
  /// corrupt.
  static Future<ProfileCacheEntry?> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if ((json['userId'] as String?) != userId) return null;

      final rawHistory = json['matchHistory'];
      final history = rawHistory is List
          ? rawHistory
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];

      return ProfileCacheEntry(
        rating: (json['rating'] as num?)?.toInt() ?? 1200,
        ratingDelta: (json['ratingDelta'] as num?)?.toInt() ?? 0,
        winStreak: (json['winStreak'] as num?)?.toInt() ?? 0,
        matchHistory: history,
      );
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
