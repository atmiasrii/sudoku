const {
  isRowValid,
  isColumnValid,
  isBoxValid,
} = require('../../utils/sudokuHelpers');

function isMoveValid(board, row, col, value) {
  if (!Number.isInteger(row) || !Number.isInteger(col) || !Number.isInteger(value)) {
    return false;
  }

  if (row < 0 || row > 8 || col < 0 || col > 8 || value < 1 || value > 9) {
    return false;
  }

  return (
    isRowValid(board, row, value, col)
    && isColumnValid(board, col, value, row)
    && isBoxValid(board, row, col, value, row, col)
  );
}

function isBoardSolved(board, solution) {
  if (solution) {
    for (let row = 0; row < 9; row += 1) {
      for (let col = 0; col < 9; col += 1) {
        if (board[row][col] !== solution[row][col]) {
          return false;
        }
      }
    }
    return true;
  }

  // Fallback: validate board as a complete Sudoku solution (1..9 each row/col/box)
  for (let row = 0; row < 9; row += 1) {
    for (let col = 0; col < 9; col += 1) {
      const value = board[row][col];
      if (!Number.isInteger(value) || value < 1 || value > 9) {
        return false;
      }
      if (!isMoveValid(board, row, col, value)) {
        return false;
      }
    }
  }
  return true;
}

module.exports = {
  isMoveValid,
  isBoardSolved,
};
