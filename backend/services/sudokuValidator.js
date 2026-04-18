const { isMoveValid, isBoardSolved } = require('./sudoku/validator');

function isValidMove(board, row, col, value) {
  return isMoveValid(board, row, col, value);
}

function isBoardComplete(board, solution) {
  return isBoardSolved(board, solution);
}

module.exports = {
  isValidMove,
  isBoardComplete,
};
