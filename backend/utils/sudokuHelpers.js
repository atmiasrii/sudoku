function cloneBoard(board) {
  return board.map((row) => [...row]);
}

function createSeededRandom(seed = Date.now()) {
  let state = Number(seed) >>> 0;

  return function random() {
    // Mulberry32 PRNG
    state += 0x6D2B79F5;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function randomInt(min, max, randomFn = Math.random) {
  return Math.floor(randomFn() * (max - min + 1)) + min;
}

function shuffleNumbers(numbers, randomFn = Math.random) {
  const arr = [...numbers];
  for (let i = arr.length - 1; i > 0; i -= 1) {
    const j = Math.floor(randomFn() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

function isRowValid(board, row, value, excludeCol = -1) {
  for (let col = 0; col < 9; col += 1) {
    if (col === excludeCol) continue;
    if (board[row][col] === value) return false;
  }
  return true;
}

function isColumnValid(board, col, value, excludeRow = -1) {
  for (let row = 0; row < 9; row += 1) {
    if (row === excludeRow) continue;
    if (board[row][col] === value) return false;
  }
  return true;
}

function isBoxValid(board, row, col, value, excludeRow = -1, excludeCol = -1) {
  const boxStartRow = Math.floor(row / 3) * 3;
  const boxStartCol = Math.floor(col / 3) * 3;

  for (let r = boxStartRow; r < boxStartRow + 3; r += 1) {
    for (let c = boxStartCol; c < boxStartCol + 3; c += 1) {
      if (r === excludeRow && c === excludeCol) continue;
      if (board[r][c] === value) return false;
    }
  }

  return true;
}

module.exports = {
  cloneBoard,
  createSeededRandom,
  randomInt,
  shuffleNumbers,
  isRowValid,
  isColumnValid,
  isBoxValid,
};
