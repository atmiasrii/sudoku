const {
  cloneBoard,
  shuffleNumbers,
  isRowValid,
  isColumnValid,
  isBoxValid,
} = require('../../utils/sudokuHelpers');

function canPlace(board, row, col, value) {
  return (
    isRowValid(board, row, value)
    && isColumnValid(board, col, value)
    && isBoxValid(board, row, col, value)
  );
}

function findEmptyCell(board) {
  for (let row = 0; row < 9; row += 1) {
    for (let col = 0; col < 9; col += 1) {
      if (board[row][col] === 0) {
        return [row, col];
      }
    }
  }
  return null;
}

function solveInPlace(board, randomize = false, randomFn = Math.random) {
  const empty = findEmptyCell(board);
  if (!empty) return true;

  const [row, col] = empty;
  const values = randomize
    ? shuffleNumbers([1, 2, 3, 4, 5, 6, 7, 8, 9], randomFn)
    : [1, 2, 3, 4, 5, 6, 7, 8, 9];

  for (const value of values) {
    if (!canPlace(board, row, col, value)) continue;

    board[row][col] = value;
    if (solveInPlace(board, randomize, randomFn)) return true;
    board[row][col] = 0;
  }

  return false;
}

function solveBoard(board, options = {}) {
  const { randomize = false, randomFn = Math.random } = options;
  const working = cloneBoard(board);
  const solved = solveInPlace(working, randomize, randomFn);
  return solved ? working : null;
}

function countSolutions(board, limit = 2) {
  const working = cloneBoard(board);
  let count = 0;

  function backtrack() {
    if (count >= limit) return;

    const empty = findEmptyCell(working);
    if (!empty) {
      count += 1;
      return;
    }

    const [row, col] = empty;
    for (let value = 1; value <= 9; value += 1) {
      if (!canPlace(working, row, col, value)) continue;

      working[row][col] = value;
      backtrack();
      working[row][col] = 0;

      if (count >= limit) return;
    }
  }

  backtrack();
  return count;
}

module.exports = {
  canPlace,
  solveBoard,
  countSolutions,
};
