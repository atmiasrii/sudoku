class SudokuBoard {
  final List<List<int>> original;
  final List<List<int>> current;

  SudokuBoard({required this.original, required this.current});

  /// Returns a starter puzzle. 0 = empty cell.
  static SudokuBoard getStarterBoard() {
    List<List<int>> puzzle = [
      [0, 4, 0, 0, 7, 0, 0, 0, 0],
      [0, 1, 8, 9, 4, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 0, 0, 0],
    ];
    // Deep copy for current state
    List<List<int>> current = puzzle.map((row) => List<int>.from(row)).toList();
    return SudokuBoard(original: puzzle, current: current);
  }

  factory SudokuBoard.fromPuzzle(List<List<int>> puzzle) {
    final original = puzzle.map((row) => List<int>.from(row)).toList();
    final current = puzzle.map((row) => List<int>.from(row)).toList();
    return SudokuBoard(original: original, current: current);
  }

  List<List<int>> cloneCurrent() {
    return current.map((row) => List<int>.from(row)).toList();
  }

  /// Returns true if the cell is pre-filled and locked
  bool isCellLocked(int row, int col) {
    return original[row][col] != 0;
  }

  /// Set a cell value (if not locked)
  void setCell(int row, int col, int value) {
    if (!isCellLocked(row, col)) {
      current[row][col] = value;
    }
  }
}
