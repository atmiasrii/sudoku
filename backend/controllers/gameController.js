const { v4: uuidv4 } = require('uuid');
const { generatePuzzle } = require('../services/sudokuGenerator');
const { isValidMove, isBoardComplete } = require('../services/sudokuValidator');
const { cloneBoard } = require('../utils/sudokuHelpers');
const { storeMatchResult, getPlayerMatchHistory } = require('../services/gameService');
const { isUserId, clampInt } = require('../utils/validators');
const {
  createSession,
  getSession,
  updateProgress,
  finishSession,
} = require('../services/gameSessionService');
const {
  etDateString,
  etSeedForDate,
  etDayNumber,
  nextEtMidnightUtcIso,
} = require('../utils/etDate');

const games = {};

// One generated daily challenge per ET date, so every request that day returns
// the identical puzzle without regenerating it.
const dailyCache = {};
const DAILY_DIFFICULTY = 'hard';

function isBoardShapeValid(board) {
  return (
    Array.isArray(board)
    && board.length === 9
    && board.every((row) => Array.isArray(row) && row.length === 9)
  );
}

function sanitizeDifficulty(value) {
  return ['easy', 'medium', 'hard'].includes(value) ? value : 'medium';
}

function createGameSession({ difficulty, seed }) {
  const { puzzle, solution, seed: usedSeed } = generatePuzzle(seed, { difficulty });
  const gameId = uuidv4();

  const session = {
    gameId,
    seed: usedSeed,
    puzzle: cloneBoard(puzzle),
    solution: cloneBoard(solution),
    players: [],
    startTime: Date.now(),
    progress: {
      filledCells: 0,
      mistakes: 0,
      percentage: 0,
      updatedAt: Date.now(),
    },
  };

  games[gameId] = session;

  return {
    puzzle,
    solution,
    difficulty,
    gameId,
    seed: usedSeed,
  };
}

function parseSeed(rawSeed) {
  if (rawSeed === undefined || rawSeed === '') return undefined;
  return clampInt(rawSeed, 0, Number.MAX_SAFE_INTEGER, undefined);
}

function newGame(req, res) {
  const difficulty = sanitizeDifficulty(req.query.difficulty);
  const seed = parseSeed(req.query.seed);
  return res.json(createGameSession({ difficulty, seed }));
}

function getPuzzle(req, res) {
  const difficulty = sanitizeDifficulty(req.query.difficulty);
  const seed = parseSeed(req.query.seed);
  return res.json(createGameSession({ difficulty, seed }));
}

// Today's daily challenge. The puzzle is keyed by the ET calendar date so it is
// identical for everyone and rotates at ET midnight. `expiresAt` lets the client
// run a live countdown without doing any timezone math itself.
function dailyChallenge(req, res) {
  const date = etDateString();

  if (!dailyCache[date]) {
    const seed = etSeedForDate(date);
    const session = createGameSession({ difficulty: DAILY_DIFFICULTY, seed });
    dailyCache[date] = {
      date,
      dayNumber: etDayNumber(date),
      difficulty: DAILY_DIFFICULTY,
      seed,
      puzzle: session.puzzle,
      solution: session.solution,
      gameId: session.gameId,
    };
  }

  // expiresAt is recomputed per response (cheap) so it always reflects the
  // remaining time, while the puzzle stays cached.
  return res.json({
    ...dailyCache[date],
    expiresAt: nextEtMidnightUtcIso(),
  });
}

function validateMove(req, res) {
  const { board, row, col, value } = req.body || {};

  if (!isBoardShapeValid(board)) {
    return res.status(400).json({ valid: false, message: 'Invalid board shape' });
  }

  const valid = isValidMove(board, row, col, value);
  return res.json({ valid });
}

function checkGame(req, res) {
  const { board, gameId } = req.body || {};

  if (!gameId || !games[gameId]) {
    return res.status(404).json({ completed: false, message: 'Game not found' });
  }

  if (!isBoardShapeValid(board)) {
    return res.status(400).json({ completed: false, message: 'Invalid board shape' });
  }

  const completed = isBoardComplete(board, games[gameId].solution);
  return res.json({ completed });
}

function validateBoard(req, res) {
  const { board, gameId } = req.body || {};

  if (!isBoardShapeValid(board)) {
    return res.status(400).json({ valid: false, message: 'Invalid board shape' });
  }

  if (gameId && games[gameId]) {
    return res.json({ valid: isBoardComplete(board, games[gameId].solution) });
  }

  return res.json({ valid: isBoardComplete(board) });
}

function getHint(req, res) {
  const { board, gameId } = req.body || {};

  if (!gameId || !games[gameId]) {
    return res.status(404).json({ message: 'Game not found' });
  }

  if (!isBoardShapeValid(board)) {
    return res.status(400).json({ message: 'Invalid board shape' });
  }

  const emptyCells = [];
  for (let row = 0; row < 9; row += 1) {
    for (let col = 0; col < 9; col += 1) {
      if (board[row][col] === 0) {
        emptyCells.push({ row, col });
      }
    }
  }

  if (emptyCells.length === 0) {
    return res.status(400).json({ message: 'Board already full' });
  }

  const randomCell = emptyCells[Math.floor(Math.random() * emptyCells.length)];
  const value = games[gameId].solution[randomCell.row][randomCell.col];

  return res.json({
    row: randomCell.row,
    col: randomCell.col,
    value,
  });
}

function updateGameProgress(req, res) {
  const { gameId, filledCells, mistakes } = req.body || {};

  if (!gameId || !games[gameId]) {
    return res.status(404).json({ message: 'Game not found' });
  }

  if (!Number.isInteger(filledCells) || !Number.isInteger(mistakes)) {
    return res.status(400).json({ message: 'filledCells and mistakes must be integers' });
  }

  const totalFillable = games[gameId].puzzle.flat().filter((value) => value === 0).length || 1;
  const percentage = Math.max(0, Math.min(100, Math.round((filledCells / totalFillable) * 100)));

  games[gameId].progress = {
    filledCells,
    mistakes,
    percentage,
    updatedAt: Date.now(),
  };

  return res.json({
    gameId,
    filledCells,
    mistakes,
    percentage,
  });
}

function createMatchSession(req, res) {
  const { player1Id, player2Id } = req.body || {};

  if (!player1Id || !player2Id) {
    return res.status(400).json({ message: 'player1Id and player2Id are required' });
  }

  if (!isUserId(player1Id) || !isUserId(player2Id)) {
    return res.status(400).json({ message: 'Invalid player id' });
  }

  const session = createSession(player1Id, player2Id);
  return res.status(201).json(session);
}

function getMatchSession(req, res) {
  const { gameId } = req.params;
  const session = getSession(gameId);

  if (!session) {
    return res.status(404).json({ message: 'Session not found' });
  }

  return res.json(session);
}

function updateMatchSessionProgress(req, res) {
  const { gameId } = req.params;
  const { playerId, filledCells, mistakes, completed } = req.body || {};

  if (!playerId) {
    return res.status(400).json({ message: 'playerId is required' });
  }

  // When auth is enforced, a player may only update their own progress.
  if (req.userId && playerId !== req.userId) {
    return res.status(403).json({ message: 'Cannot update another player' });
  }

  const data = {};
  if (filledCells !== undefined) {
    if (!Number.isInteger(filledCells) || filledCells < 0 || filledCells > 81) {
      return res.status(400).json({ message: 'filledCells must be an integer between 0 and 81' });
    }
    data.filledCells = filledCells;
  }

  if (mistakes !== undefined) {
    if (!Number.isInteger(mistakes) || mistakes < 0 || mistakes > 3) {
      return res.status(400).json({ message: 'mistakes must be an integer between 0 and 3' });
    }
    data.mistakes = mistakes;
  }

  if (completed !== undefined) data.completed = completed;

  const session = updateProgress(gameId, playerId, data);
  if (!session) {
    return res.status(404).json({ message: 'Session or player not found' });
  }

  // If completed was true, updateProgress returns finished session data.
  if (data.completed === true) {
    return res.json({ finished: true, result: session });
  }

  return res.json({ finished: false, session });
}

function finishMatchSession(req, res) {
  const { gameId } = req.params;
  const { winnerId } = req.body || {};

  if (!winnerId) {
    return res.status(400).json({ message: 'winnerId is required' });
  }

  if (!isUserId(winnerId)) {
    return res.status(400).json({ message: 'Invalid winner id' });
  }

  const result = finishSession(gameId, winnerId);
  if (!result) {
    return res.status(404).json({ message: 'Session not found' });
  }

  return res.json(result);
}

async function storeMatchResultController(req, res) {
  try {
    const {
      seed,
      player1_id: player1Id,
      player2_id: player2Id,
      winner_id: winnerId,
      duration,
      mistakes,
    } = req.body || {};

    if (!player1Id || !player2Id) {
      return res.status(400).json({ message: 'player1_id and player2_id are required' });
    }

    if (!isUserId(player1Id) || !isUserId(player2Id)) {
      return res.status(400).json({ message: 'Invalid player id' });
    }

    if (winnerId && !isUserId(winnerId)) {
      return res.status(400).json({ message: 'Invalid winner id' });
    }

    // winner must be one of the two players — blocks crediting an unrelated id.
    if (winnerId && winnerId !== player1Id && winnerId !== player2Id) {
      return res.status(400).json({ message: 'winner_id must be one of the players' });
    }

    // When auth is enforced, the reporter must be a participant in the match.
    if (req.userId && req.userId !== player1Id && req.userId !== player2Id) {
      return res.status(403).json({ message: 'Not a participant in this match' });
    }

    const match = await storeMatchResult({
      seed: clampInt(seed, 0, Number.MAX_SAFE_INTEGER, 0),
      player1_id: player1Id,
      player2_id: player2Id,
      winner_id: winnerId,
      duration: clampInt(duration, 0, 86400, 0),
      mistakes: clampInt(mistakes, 0, 999, 0),
    });

    return res.status(201).json(match);
  } catch (error) {
    console.error('storeMatchResultController error:', error);
    return res.status(500).json({ message: 'Failed to store match result' });
  }
}

async function getMatchHistoryController(req, res) {
  try {
    const userId = req.params.id;

    if (!isUserId(userId)) {
      return res.status(400).json({ message: 'Invalid user id' });
    }

    const matches = await getPlayerMatchHistory(userId);
    return res.json({ matches });
  } catch (error) {
    console.error('getMatchHistoryController error:', error);
    return res.status(500).json({ message: 'Failed to fetch match history' });
  }
}

module.exports = {
  games,
  newGame,
  getPuzzle,
  validateMove,
  validateBoard,
  checkGame,
  getHint,
  updateGameProgress,
  createMatchSession,
  getMatchSession,
  updateMatchSessionProgress,
  finishMatchSession,
  storeMatchResultController,
  getMatchHistoryController,
  dailyChallenge,
};
