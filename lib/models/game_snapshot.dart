/// A serializable snapshot of an in-progress game. Persisted while a game is
/// active so the player returns to the same board if the app is killed or loses
/// network. Cleared once the game ends or the player leaves to the lobby.
class GameSnapshot {
  final String userId;
  final String gameId;
  final String difficulty;
  final bool multiplayer;
  final List<List<int>> puzzle; // original (locked) cells
  final List<List<int>> current; // player-filled board
  final List<List<int>>? solution;
  final int elapsedSeconds;
  final int mistakes;
  final Map<String, List<int>> notes;
  final List<List<int>> moves; // each: [row, col, prevValue]
  final String playerName;
  final String opponentName;
  final int playerRating;
  final int opponentRating;
  final String? opponentId;
  final int savedAt; // epoch ms

  GameSnapshot({
    required this.userId,
    required this.gameId,
    required this.difficulty,
    required this.multiplayer,
    required this.puzzle,
    required this.current,
    this.solution,
    required this.elapsedSeconds,
    required this.mistakes,
    required this.notes,
    required this.moves,
    required this.playerName,
    required this.opponentName,
    required this.playerRating,
    required this.opponentRating,
    this.opponentId,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'gameId': gameId,
        'difficulty': difficulty,
        'multiplayer': multiplayer,
        'puzzle': puzzle,
        'current': current,
        'solution': solution,
        'elapsedSeconds': elapsedSeconds,
        'mistakes': mistakes,
        'notes': notes,
        'moves': moves,
        'playerName': playerName,
        'opponentName': opponentName,
        'playerRating': playerRating,
        'opponentRating': opponentRating,
        'opponentId': opponentId,
        'savedAt': savedAt,
      };

  static List<List<int>> _toBoard(dynamic raw) {
    return (raw as List)
        .map((row) => (row as List).map((c) => (c as num).toInt()).toList())
        .toList();
  }

  factory GameSnapshot.fromJson(Map<String, dynamic> json) {
    final notesRaw = json['notes'] as Map? ?? const {};
    final movesRaw = json['moves'] as List? ?? const [];
    return GameSnapshot(
      userId: json['userId'] as String,
      gameId: json['gameId'] as String,
      difficulty: (json['difficulty'] ?? 'ranked') as String,
      multiplayer: json['multiplayer'] == true,
      puzzle: _toBoard(json['puzzle']),
      current: _toBoard(json['current']),
      solution: json['solution'] == null ? null : _toBoard(json['solution']),
      elapsedSeconds: (json['elapsedSeconds'] as num?)?.toInt() ?? 0,
      mistakes: (json['mistakes'] as num?)?.toInt() ?? 0,
      notes: notesRaw.map(
        (key, value) => MapEntry(
          key.toString(),
          (value as List).map((e) => (e as num).toInt()).toList(),
        ),
      ),
      moves: movesRaw
          .map((m) => (m as List).map((e) => (e as num).toInt()).toList())
          .toList(),
      playerName: (json['playerName'] ?? 'You') as String,
      opponentName: (json['opponentName'] ?? 'Opponent') as String,
      playerRating: (json['playerRating'] as num?)?.toInt() ?? 1200,
      opponentRating: (json['opponentRating'] as num?)?.toInt() ?? 1200,
      opponentId: json['opponentId'] as String?,
      savedAt: (json['savedAt'] as num?)?.toInt() ?? 0,
    );
  }
}
