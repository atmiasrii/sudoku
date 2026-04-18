const { assert, runSuite, deepClone } = require('./_runner');
const { generatePuzzle } = require('../services/sudokuGenerator');
const { solveBoard, countSolutions } = require('../services/sudoku/solver');
const { isBoardComplete } = require('../services/sudokuValidator');

async function run() {
  await runSuite('Sudoku Engine', [
    {
      name: 'generatePuzzle(seed) is deterministic',
      run: async () => {
        const first = generatePuzzle(123456);
        const second = generatePuzzle(123456);
        assert.deepStrictEqual(first.puzzle, second.puzzle);
        assert.deepStrictEqual(first.solution, second.solution);
      },
    },
    {
      name: 'generatePuzzle(seed1) differs from generatePuzzle(seed2)',
      run: async () => {
        const first = generatePuzzle(111111);
        const second = generatePuzzle(222222);
        assert.notDeepStrictEqual(first.puzzle, second.puzzle);
      },
    },
    {
      name: 'generated puzzle has unique solution',
      run: async () => {
        const { puzzle } = generatePuzzle(333333);
        const solutionCount = countSolutions(puzzle, 2);
        assert.strictEqual(solutionCount, 1);
      },
    },
    {
      name: 'solver solves generated puzzles correctly',
      run: async () => {
        const { puzzle, solution } = generatePuzzle(444444);
        const solved = solveBoard(puzzle);
        assert.ok(solved);
        assert.deepStrictEqual(solved, solution);
      },
    },
    {
      name: 'validateBoard true only for correct solution',
      run: async () => {
        const { solution } = generatePuzzle(555555);
        const valid = isBoardComplete(solution, solution);
        assert.strictEqual(valid, true);

        const incorrect = deepClone(solution);
        incorrect[0][0] = incorrect[0][0] % 9 + 1;
        assert.strictEqual(isBoardComplete(incorrect, solution), false);
      },
    },
    {
      name: 'invalid boards are rejected (edge cases)',
      run: async () => {
        const { solution } = generatePuzzle(666666);
        const empty = Array.from({ length: 9 }, () => Array(9).fill(0));
        const partial = deepClone(solution);
        partial[0][0] = 0;
        const malformed = [[1, 2, 3]];

        assert.strictEqual(isBoardComplete(empty, solution), false);
        assert.strictEqual(isBoardComplete(partial, solution), false);
        assert.strictEqual(isBoardComplete(malformed, solution), false);
      },
    },
  ]);
}

if (require.main === module) {
  run().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}

module.exports = { run };
