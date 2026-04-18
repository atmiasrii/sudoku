import '../models/sudoku_board.dart';

class SudokuValidator {
  /// Checks if the board is solved correctly (no zeros, all valid)
  static bool isSolved(SudokuBoard board) {
    for (int row = 0; row < 9; row++) {
      for (int col = 0; col < 9; col++) {
        int value = board.current[row][col];
        if (value == 0 || !_isValid(board, row, col, value)) {
          return false;
        }
      }
    }
    return true;
  }

  /// Checks if placing [value] at ([row], [col]) is valid
  static bool _isValid(SudokuBoard board, int row, int col, int value) {
    // Check row
    for (int c = 0; c < 9; c++) {
      if (c != col && board.current[row][c] == value) return false;
    }
    // Check column
    for (int r = 0; r < 9; r++) {
      if (r != row && board.current[r][col] == value) return false;
    }
    // Check 3x3 box
    int boxRow = (row ~/ 3) * 3;
    int boxCol = (col ~/ 3) * 3;
    for (int r = boxRow; r < boxRow + 3; r++) {
      for (int c = boxCol; c < boxCol + 3; c++) {
        if ((r != row || c != col) && board.current[r][c] == value)
          return false;
      }
    }
    return true;
  }
}
