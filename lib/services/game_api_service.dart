import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/game_session.dart';

class GameApiService {
  static const String _baseUrl = 'http://192.168.0.103:4000/api';

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

  static Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    final uri = Uri.parse('$_baseUrl/users/$userId');
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      return null;
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> getUserMatchHistory(
      String userId) async {
    final uri = Uri.parse('$_baseUrl/users/$userId/matches');
    final response = await http.get(uri);

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
  }
}
