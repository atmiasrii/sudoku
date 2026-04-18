class GameState {
  final List<List<int>> puzzle;
  final List<List<int>> solution;
  final List<List<int>> board;
  final DateTime startTime;
  final int mistakes;
  final bool completed;

  const GameState({
    required this.puzzle,
    required this.solution,
    required this.board,
    required this.startTime,
    required this.mistakes,
    required this.completed,
  });

  GameState copyWith({
    List<List<int>>? puzzle,
    List<List<int>>? solution,
    List<List<int>>? board,
    DateTime? startTime,
    int? mistakes,
    bool? completed,
  }) {
    return GameState(
      puzzle: puzzle ?? this.puzzle,
      solution: solution ?? this.solution,
      board: board ?? this.board,
      startTime: startTime ?? this.startTime,
      mistakes: mistakes ?? this.mistakes,
      completed: completed ?? this.completed,
    );
  }
}
