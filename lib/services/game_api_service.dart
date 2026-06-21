import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/game_session.dart';

class GameApiService {
  static final String _baseUrl = ApiConfig.apiBaseUrl;

  static Future<GameSession> newGame(String difficulty, {int? seed}) async {
    final seedQuery = seed == null ? '' : '&seed=$seed';
    final uri = Uri.parse('$_baseUrl/puzzle?difficulty=$difficulty$seedQuery');
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Failed to create game');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return GameSession.fromJson(data);
  }

  /// Today's daily challenge: puzzle/solution/gameId/difficulty (consumable by
  /// [GameSession.fromJson]) plus `expiresAt` (UTC ISO, next ET midnight) and
  /// `dayNumber`. Returns null on failure so the home screen can fall back.
  static Future<Map<String, dynamic>?> getDailyChallenge() async {
    final uri = Uri.parse('$_baseUrl/daily');
    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> validateMove({
    required List<List<int>> board,
    required int row,
    required int col,
    required int value,
  }) async {
    final uri = Uri.parse('$_baseUrl/game/validate');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'board': board,
        'row': row,
        'col': col,
        'value': value,
      }),
    );

    if (response.statusCode != 200) {
      return false;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['valid'] == true;
  }

  static Future<bool> checkGame({
    required List<List<int>> board,
    required String gameId,
  }) async {
    final uri = Uri.parse('$_baseUrl/game/check');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'board': board,
        'gameId': gameId,
      }),
    );

    if (response.statusCode != 200) {
      return false;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['completed'] == true;
  }

  static Future<bool> validateBoard({
    required List<List<int>> board,
    String? gameId,
  }) async {
    final uri = Uri.parse('$_baseUrl/validate');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'board': board,
        if (gameId != null) 'gameId': gameId,
      }),
    );

    if (response.statusCode != 200) {
      return false;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['valid'] == true;
  }

  static Future<Map<String, dynamic>?> updateGameProgress({
    required String gameId,
    required int filledCells,
    required int mistakes,
  }) async {
    final uri = Uri.parse('$_baseUrl/game/update');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'gameId': gameId,
        'filledCells': filledCells,
        'mistakes': mistakes,
      }),
    );

    if (response.statusCode != 200) {
      return null;
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, int>?> hint({
    required List<List<int>> board,
    required String gameId,
  }) async {
    final uri = Uri.parse('$_baseUrl/game/hint');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'board': board,
        'gameId': gameId,
      }),
    );

    if (response.statusCode != 200) {
      return null;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return {
      'row': data['row'] as int,
      'col': data['col'] as int,
      'value': data['value'] as int,
    };
  }

  /// Create the backend profile row for an authenticated user. Safe to call on
  /// every login — a 409 (already exists) is treated as success.
  ///
  /// [allowSuffix] tells the backend to auto-suffix a clashing username instead
  /// of failing — used by the login auto-derive path, NOT explicit signup.
  static Future<bool> ensureUserProfile(
    String userId,
    String username, {
    String? accessToken,
    bool allowSuffix = false,
  }) async {
    final uri = Uri.parse('$_baseUrl/users');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'userId': userId,
        'username': username,
        'allowSuffix': allowSuffix,
      }),
    );
    return response.statusCode == 201 || response.statusCode == 409;
  }

  /// Whether [username] is free (case-insensitive). Returns false on a taken
  /// name or any error (fail-closed for the pre-check; the unique index is the
  /// real guard).
  static Future<bool> isUsernameAvailable(String username) async {
    final uri = Uri.parse(
        '$_baseUrl/users/username-available?username=${Uri.encodeQueryComponent(username)}');
    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['available'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getLeaderboard({
    int limit = 25,
  }) async {
    final uri = Uri.parse('$_baseUrl/leaderboard?limit=$limit');
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      return <Map<String, dynamic>>[];
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rawPlayers = data['players'];
    if (rawPlayers is! List) {
      return <Map<String, dynamic>>[];
    }

    return rawPlayers
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    final uri = Uri.parse('$_baseUrl/users/$userId');
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 7));

      if (response.statusCode != 200) {
        return null;
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getUserMatchHistory(
      String userId) async {
    final uri = Uri.parse('$_baseUrl/users/$userId/matches');
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 7));

      if (response.statusCode != 200) {
        return <Map<String, dynamic>>[];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawMatches = data['matches'];
      if (rawMatches is! List) {
        return <Map<String, dynamic>>[];
      }

      return rawMatches
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }
}
