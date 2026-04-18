class GameSession {
  final List<List<int>> puzzle;
  final List<List<int>>? solution;
  final Map<String, dynamic>? playersMeta;
  final String difficulty;
  final String gameId;
  final int? seed;

  GameSession({
    required this.puzzle,
    this.solution,
    this.playersMeta,
    required this.difficulty,
    required this.gameId,
    this.seed,
  });

  factory GameSession.fromJson(Map<String, dynamic> json) {
    List<List<int>> toBoard(dynamic raw) {
      return (raw as List)
          .map((row) => (row as List).map((cell) => cell as int).toList())
          .toList();
    }

    return GameSession(
      puzzle: toBoard(json['puzzle']),
      solution: json['solution'] == null ? null : toBoard(json['solution']),
      playersMeta: json['playersMeta'] is Map
          ? Map<String, dynamic>.from(json['playersMeta'] as Map)
          : null,
      difficulty: (json['difficulty'] ?? 'medium') as String,
      gameId: json['gameId'] as String,
      seed: json['seed'] is int ? json['seed'] as int : null,
    );
  }

  factory GameSession.fromMatchFound(Map<String, dynamic> json) {
    List<List<int>> toBoard(dynamic raw) {
      return (raw as List)
          .map((row) => (row as List).map((cell) => cell as int).toList())
          .toList();
    }

    return GameSession(
      puzzle: toBoard(json['puzzle']),
      solution: null,
      playersMeta: json['playersMeta'] is Map
          ? Map<String, dynamic>.from(json['playersMeta'] as Map)
          : null,
      difficulty: 'ranked',
      gameId: json['gameId'] as String,
      seed: json['seed'] is int ? json['seed'] as int : null,
    );
  }
}
