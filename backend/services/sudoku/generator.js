const {
  cloneBoard,
  createSeededRandom,
  randomInt,
  shuffleNumbers,
} = require('../../utils/sudokuHelpers');
const { solveBoard, countSolutions } = require('./solver');
const { getRemovalCount } = require('./difficulty');

function generateSolvedBoard(seed = Date.now()) {
  const board = Array.from({ length: 9 }, () => Array(9).fill(0));
  const randomFn = createSeededRandom(seed);
  const solved = solveBoard(board, { randomize: true, randomFn });

  if (!solved) {
    throw new Error('Failed to generate solved Sudoku board');
  }

  return solved;
}

function normalizePuzzleInput(seedInput, options = {}) {
  if (typeof seedInput === 'string' && ['easy', 'medium', 'hard'].includes(seedInput)) {
    return {
      seed: randomInt(100000, 999999),
      difficulty: seedInput,
    };
  }

  const difficulty = options.difficulty || 'medium';
  const parsedSeed = Number(seedInput);

  return {
    seed: Number.isFinite(parsedSeed) ? parsedSeed : randomInt(100000, 999999),
    difficulty,
  };
}

function generatePuzzle(seedInput, options = {}) {
  const { seed, difficulty } = normalizePuzzleInput(seedInput, options);
  const randomFn = createSeededRandom(seed);
  const solution = generateSolvedBoard(seed);
  const puzzle = cloneBoard(solution);

  const targetRemovals = getRemovalCount(difficulty);
  const cellIndexes = shuffleNumbers(
    Array.from({ length: 81 }, (_, i) => i),
    randomFn,
  );

  let removed = 0;
  for (const index of cellIndexes) {
    if (removed >= targetRemovals) break;

    const row = Math.floor(index / 9);
    const col = index % 9;
    const previous = puzzle[row][col];

    puzzle[row][col] = 0;
    const solutions = countSolutions(puzzle, 2);

    if (solutions !== 1) {
      puzzle[row][col] = previous;
      continue;
    }

    removed += 1;
  }

  return {
    puzzle,
    solution,
    seed,
  };
}

module.exports = {
  generateSolvedBoard,
  generatePuzzle,
};
