import 'dart:async';

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../widgets/user_avatar.dart';

import '../logic/sudoku_validator.dart';
import '../models/game_session.dart';
import '../models/game_snapshot.dart';
import '../models/sudoku_board.dart';
import '../services/active_game_store.dart';
import '../services/analytics_service.dart';
import '../services/game_api_service.dart';
import '../services/multiplayer_socket_service.dart';
import 'victory_screen.dart';
import '../widgets/sudoku_grid.dart';

class GameScreen extends StatefulWidget {
  final GameSession? initialSession;
  final GameSnapshot? restoreFrom;
  final bool highlightMistakes;
  final bool timerEnabled;
  final String? currentUserId;
  final bool multiplayerEnabled;

  const GameScreen({
    super.key,
    this.initialSession,
    this.restoreFrom,
    required this.highlightMistakes,
    required this.timerEnabled,
    this.currentUserId,
    this.multiplayerEnabled = false,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with WidgetsBindingObserver {
  final MultiplayerSocketService _socketService =
      MultiplayerSocketService.instance;

  late SudokuBoard _board;
  List<List<int>>? _solution;
  String? _gameId;
  String _difficulty = 'ranked';
  int? _selectedRow;
  int? _selectedCol;
  final List<_Move> _moveHistory = [];
  final List<StreamSubscription> _subs = [];

  Timer? _timer;
  Timer? _finishTimeout;
  int _elapsedSeconds = 0;
  int _mistakes = 0;
  bool _gameEnded = false;
  bool _lost = false;
  bool _awaitingFinish = false;
  bool _gameStateErrorShown = false;
  bool _noteMode = false;
  bool _postMatchPracticeMode = false;
  bool _showBackAfterMatch = false;
  bool _hideRatings = false;

  final Map<String, Set<int>> _cellNotes = {};

  String _playerName = 'You';
  String _opponentName = 'Opponent';
  int _playerRating = 1200;
  int _opponentRating = 1200;
  int _opponentProgressPercent = 0;
  int _lastRatingDelta = 0;
  int _opponentMistakes = 0;
  String? _opponentId;

  bool get _isMultiplayer => widget.multiplayerEnabled;

  List<List<int>>? _parseBoard(dynamic raw) {
    if (raw is! List || raw.length != 9) return null;

    final parsed = <List<int>>[];
    for (final row in raw) {
      if (row is! List || row.length != 9) return null;
      final parsedRow = <int>[];
      for (final cell in row) {
        if (cell is! num) return null;
        final value = cell.toInt();
        if (value < 0 || value > 9) return null;
        parsedRow.add(value);
      }
      parsed.add(parsedRow);
    }

    return parsed;
  }

  void _applyBoardSnapshot(dynamic rawBoard) {
    final board = _parseBoard(rawBoard);
    if (board == null) return;

    for (int row = 0; row < 9; row++) {
      for (int col = 0; col < 9; col++) {
        _board.setCell(row, col, board[row][col]);
      }
    }
  }

  void _applyPlayersMeta(dynamic rawMeta) {
    if (rawMeta is! Map) return;

    final me = widget.currentUserId;
    if (me == null) return;

    final meta = Map<String, dynamic>.from(rawMeta);
    final myMeta = meta[me];
    if (myMeta is Map) {
      final name = myMeta['username']?.toString();
      final rating = myMeta['rating'];
      if (name != null && name.isNotEmpty) {
        _playerName = name;
      }
      if (rating is num) {
        _playerRating = rating.toInt();
      }
    }

    for (final entry in meta.entries) {
      final id = entry.key;
      if (id == me) continue;

      _opponentId = id;
      final opponentMeta = entry.value;
      if (opponentMeta is Map) {
        final name = opponentMeta['username']?.toString();
        final rating = opponentMeta['rating'];
        if (name != null && name.isNotEmpty) {
          _opponentName = name;
        }
        if (rating is num) {
          _opponentRating = rating.toInt();
        }
      }
      break;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.restoreFrom != null) {
      _restoreFromSnapshot(widget.restoreFrom!);
    } else {
      _loadSession(widget.initialSession);
    }
    _startTimerIfNeeded();
    if (_isMultiplayer) {
      _bindMultiplayerEvents();
      if (widget.currentUserId != null && _gameId != null) {
        if (widget.restoreFrom != null) {
          // Cold restore: the socket was torn down when the app closed, so
          // reconnect it before asking the server to rejoin the match.
          _reconnectAfterRestore();
        } else {
          _socketService.reconnectGame(widget.currentUserId!, _gameId!);
        }
      }
    }
  }

  Future<void> _reconnectAfterRestore() async {
    final userId = widget.currentUserId;
    final gameId = _gameId;
    if (userId == null || gameId == null) return;
    try {
      await _socketService.connect(userId);
      if (!mounted) return;
      _socketService.reconnectGame(userId, gameId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not reconnect to the match. Showing your last board.')),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App going to background / being killed: persist so we can resume later.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _persistSnapshot();
    }
  }

  void _restoreFromSnapshot(GameSnapshot s) {
    _board = SudokuBoard(
      original: s.puzzle.map((r) => List<int>.from(r)).toList(),
      current: s.current.map((r) => List<int>.from(r)).toList(),
    );
    _solution = s.solution?.map((r) => List<int>.from(r)).toList();
    _gameId = s.gameId;
    _difficulty = s.difficulty;
    _selectedRow = 4;
    _selectedCol = 4;
    _moveHistory
      ..clear()
      ..addAll(s.moves.map((m) => _Move(m[0], m[1], m[2], false)));
    _elapsedSeconds = s.elapsedSeconds;
    _mistakes = s.mistakes;
    _gameEnded = false;
    _lost = false;
    _awaitingFinish = false;
    _gameStateErrorShown = false;
    _noteMode = false;
    _postMatchPracticeMode = false;
    _showBackAfterMatch = false;
    _cellNotes
      ..clear()
      ..addAll(s.notes.map((k, v) => MapEntry(k, v.toSet())));
    _playerName = s.playerName;
    _opponentName = s.opponentName;
    _playerRating = s.playerRating;
    _opponentRating = s.opponentRating;
    _opponentId = s.opponentId;
    _opponentProgressPercent = 0;
    _opponentMistakes = 0;
  }

  void _persistSnapshot() {
    final userId = widget.currentUserId;
    // Nothing worth resuming: no identity, no server game, already finished, or
    // just solving the board for fun after the match ended.
    if (userId == null ||
        _gameId == null ||
        _gameEnded ||
        _awaitingFinish ||
        _postMatchPracticeMode) {
      return;
    }
    final snapshot = GameSnapshot(
      userId: userId,
      gameId: _gameId!,
      difficulty: _difficulty,
      multiplayer: _isMultiplayer,
      puzzle: _board.original.map((r) => List<int>.from(r)).toList(),
      current: _board.cloneCurrent(),
      solution: _solution?.map((r) => List<int>.from(r)).toList(),
      elapsedSeconds: _elapsedSeconds,
      mistakes: _mistakes,
      notes: _cellNotes.map((k, v) => MapEntry(k, v.toList())),
      moves: _moveHistory
          .map((m) => [m.row, m.col, m.prevValue])
          .toList(),
      playerName: _playerName,
      opponentName: _opponentName,
      playerRating: _playerRating,
      opponentRating: _opponentRating,
      opponentId: _opponentId,
      savedAt: DateTime.now().millisecondsSinceEpoch,
    );
    ActiveGameStore.save(snapshot);
  }

  @override
  void didUpdateWidget(covariant GameScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSession?.gameId != widget.initialSession?.gameId) {
      _loadSession(widget.initialSession);
    }
    if (oldWidget.timerEnabled != widget.timerEnabled) {
      _timer?.cancel();
      _startTimerIfNeeded();
    }
  }

  @override
  void dispose() {
    // Leaving the screen normally (pop / surrender / finished) means there is
    // nothing to resume — a process-kill skips dispose, so the snapshot saved
    // on the last pause survives for next launch.
    ActiveGameStore.clear();
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _finishTimeout?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    if (_isMultiplayer) {
      _socketService.disconnect();
    }
    super.dispose();
  }

  void _bindMultiplayerEvents() {
    _subs.add(_socketService.progressUpdateStream.listen((payload) {
      final gameId = payload['gameId']?.toString();
      if (gameId == null || gameId != _gameId || !mounted) return;

      final session = payload['session'] ?? payload['result'];
      if (session is Map) {
        _syncProgressFromSessionMap(Map<String, dynamic>.from(session));
      }
    }));

    _subs.add(_socketService.gameEndStream.listen((payload) async {
      final gameId = payload['gameId']?.toString() ?? _gameId;
      if (gameId == null || gameId != _gameId || !mounted) return;

      final winnerId = payload['winnerId']?.toString();
      final loserId = payload['loserId']?.toString();
      final reason = payload['reason']?.toString() ?? 'completed';
      final ratingUpdate = payload['ratingUpdate'];

      _finishTimeout?.cancel();
      setState(() {
        _gameEnded = true;
        _awaitingFinish = false;
        final me = widget.currentUserId;
        _lost = me != null && winnerId != null ? winnerId != me : false;

        if (me != null && winnerId != null && loserId != null) {
          _opponentId = me == winnerId ? loserId : winnerId;
        }

        if (ratingUpdate is Map) {
          final ratings = ratingUpdate['ratings'];
          if (ratings is Map) {
            final me = widget.currentUserId;
            if (me != null && ratings[me] is num) {
              _playerRating = (ratings[me] as num).toInt();
            }
            if (_opponentId != null && ratings[_opponentId] is num) {
              _opponentRating = (ratings[_opponentId] as num).toInt();
            }
          }
          // Capture the delta from game_end itself so the result screen shows
          // the correct +/- immediately (it now ships with game_end instead of
          // arriving later via a separate rating_update).
          final deltas = ratingUpdate['deltas'];
          final me = widget.currentUserId;
          if (deltas is Map && me != null && deltas[me] is num) {
            _lastRatingDelta = (deltas[me] as num).toInt();
          }
        }
      });

      if (!mounted) return;

      if (reason == 'opponent_disconnected' && !_lost) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Opponent disconnected. You win by forfeit.')),
        );
      }

      await _openResultScreen(
        won: !_lost,
        allowContinueOnClose: true,
      );
    }));

    _subs.add(_socketService.ratingUpdateStream.listen((payload) {
      if (!mounted) return;
      final ratings = payload['ratings'];
      final deltas = payload['deltas'];
      if (ratings is! Map) return;

      setState(() {
        final me = widget.currentUserId;
        if (me != null && ratings[me] is num) {
          _playerRating = (ratings[me] as num).toInt();
          if (deltas is Map && deltas[me] is num) {
            _lastRatingDelta = (deltas[me] as num).toInt();
          }
        }
        if (_opponentId != null && ratings[_opponentId] is num) {
          _opponentRating = (ratings[_opponentId] as num).toInt();
        }
      });
    }));

    _subs.add(_socketService.opponentDisconnectedStream.listen((payload) {
      final gameId = payload['gameId']?.toString();
      if (gameId != _gameId || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Opponent disconnected. Waiting for reconnect...')),
      );
    }));

    _subs.add(_socketService.opponentReconnectedStream.listen((payload) {
      final gameId = payload['gameId']?.toString();
      if (gameId != _gameId || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opponent reconnected. Match resumed.')),
      );
    }));

    _subs.add(_socketService.progressRejectedStream.listen((payload) {
      final gameId = payload['gameId']?.toString();
      if (gameId != _gameId || !mounted) return;
      final message = payload['message']?.toString() ?? 'Progress rejected';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      _finishTimeout?.cancel();
      setState(() {
        _awaitingFinish = false;
      });
    }));

    _subs.add(_socketService.connectionStream.listen((connected) {
      if (!mounted) return;
      if (connected &&
          _gameId != null &&
          widget.currentUserId != null &&
          !_gameEnded) {
        _socketService.reconnectGame(widget.currentUserId!, _gameId!);
      }
    }));

    _subs.add(_socketService.reconnectRequiredStream.listen((payload) {
      final gameId = payload['gameId']?.toString();
      if (gameId == null || gameId != _gameId || !mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Session reconnect required. Syncing latest game state.'),
        ),
      );

      if (widget.currentUserId != null) {
        _socketService.reconnectGame(widget.currentUserId!, gameId);
      }
    }));

    _subs.add(_socketService.gameStateErrorStream.listen((payload) async {
      if (!mounted || _gameStateErrorShown) return;

      _gameStateErrorShown = true;
      final message = payload['message']?.toString() ??
          'Could not sync multiplayer game state.';

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('Game State Error'),
            content: Text(message),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back'),
              ),
            ],
          );
        },
      );

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }));

    _subs.add(_socketService.gameStateStream.listen((payload) {
      final gameId = payload['gameId']?.toString();
      if (gameId == null || gameId != _gameId || !mounted) return;

      final board = payload['board'];
      if (board != null) {
        _applyBoardSnapshot(board);
      }

      _applyPlayersMeta(payload['playersMeta']);

      final progress = payload['progress'];
      if (progress is Map) {
        _syncProgressFromSessionMap({'progress': progress});
      } else if (mounted) {
        setState(() {});
      }
    }));
  }

  void _syncProgressFromSessionMap(Map<String, dynamic> session) {
    _applyPlayersMeta(session['playersMeta']);
    if (session['board'] != null) {
      _applyBoardSnapshot(session['board']);
    }

    final progress = session['progress'];
    if (progress is! Map) return;

    final me = widget.currentUserId;
    if (me == null) return;

    final myProgress = progress[me];
    final opponentEntry = progress.entries
        .where((entry) => entry.key.toString() != me)
        .cast<MapEntry<dynamic, dynamic>>()
        .toList();

    if (myProgress is Map) {
      final myMistakes = myProgress['mistakes'];
      if (myMistakes is num) {
        _mistakes = myMistakes.toInt();
      }
    }

    if (opponentEntry.isNotEmpty) {
      final key = opponentEntry.first.key.toString();
      final value = opponentEntry.first.value;
      _opponentId = key;
      if (_opponentName == 'Opponent') {
        _opponentName = key.length > 10
            ? 'Opponent ${key.substring(key.length - 4)}'
            : 'Opponent';
      }

      if (value is Map) {
        final filled = value['filledCells'];
        final mistakes = value['mistakes'];
        if (filled is num) {
          final total = _totalFillableCells == 0 ? 1 : _totalFillableCells;
          _opponentProgressPercent =
              ((filled.toInt() / total) * 100).round().clamp(0, 100);
        }
        if (mistakes is num) {
          _opponentMistakes = mistakes.toInt();
        }
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _loadSession(GameSession? session) {
    if (session == null) {
      _board = SudokuBoard.getStarterBoard();
      _solution = _board.current.map((row) => List<int>.from(row)).toList();
      _gameId = null;
      _difficulty = 'ranked';
      _selectedRow = 4;
      _selectedCol = 4;
      _moveHistory.clear();
      _elapsedSeconds = 0;
      _mistakes = 0;
      _gameEnded = false;
      _lost = false;
      _awaitingFinish = false;
      _gameStateErrorShown = false;
      _noteMode = false;
      _postMatchPracticeMode = false;
      _showBackAfterMatch = false;
      _cellNotes.clear();
      _playerName = 'You';
      _opponentName = 'Opponent';
      _playerRating = 1200;
      _opponentRating = 1200;
      _opponentId = null;
      _opponentProgressPercent = 0;
      _opponentMistakes = 0;
      return;
    }

    _board = SudokuBoard.fromPuzzle(session.puzzle);
    _solution = session.solution?.map((row) => List<int>.from(row)).toList();
    _gameId = session.gameId;
    _difficulty = session.difficulty;
    _selectedRow = 4;
    _selectedCol = 4;
    _moveHistory.clear();
    _elapsedSeconds = 0;
    _mistakes = 0;
    _gameEnded = false;
    _lost = false;
    _awaitingFinish = false;
    _gameStateErrorShown = false;
    _noteMode = false;
    _postMatchPracticeMode = false;
    _showBackAfterMatch = false;
    _cellNotes.clear();
    _playerName = 'You';
    _opponentName = 'Opponent';
    _playerRating = 1200;
    _opponentRating = 1200;
    _opponentId = null;
    _applyPlayersMeta(session.playersMeta);
    _opponentProgressPercent = 0;
    _opponentMistakes = 0;
  }

  void _startTimerIfNeeded() {
    if (!widget.timerEnabled) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds += 1;
      });
    });
  }

  String _cellKey(int row, int col) => '$row-$col';

  String _noteKey(int row, int col) => '$row-$col';

  int get _totalFillableCells {
    int count = 0;
    for (int row = 0; row < 9; row++) {
      for (int col = 0; col < 9; col++) {
        if (_board.original[row][col] == 0) count++;
      }
    }
    return count;
  }

  int get _filledFillableCells {
    int count = 0;
    for (int row = 0; row < 9; row++) {
      for (int col = 0; col < 9; col++) {
        if (_board.original[row][col] != 0) continue;
        final v = _board.current[row][col];
        if (v == 0) continue;
        final correct = _solution != null
            ? v == _solution![row][col]
            : !_displayInvalidCells.contains(_cellKey(row, col));
        if (correct) count++;
      }
    }
    return count;
  }

  int get _playerProgressPercent {
    final total = _totalFillableCells;
    if (total == 0) return 100;
    return ((_filledFillableCells / total) * 100).round().clamp(0, 100);
  }

  bool _isSolvedLocally() {
    if (_solution != null) {
      for (int row = 0; row < 9; row++) {
        for (int col = 0; col < 9; col++) {
          if (_board.current[row][col] != _solution![row][col]) return false;
        }
      }
      return true;
    }

    return SudokuValidator.isSolved(_board);
  }

  bool _isValidPlacement(int row, int col, int value) {
    for (int c = 0; c < 9; c++) {
      if (c != col && _board.current[row][c] == value) return false;
    }
    for (int r = 0; r < 9; r++) {
      if (r != row && _board.current[r][col] == value) return false;
    }

    final boxRow = (row ~/ 3) * 3;
    final boxCol = (col ~/ 3) * 3;
    for (int r = boxRow; r < boxRow + 3; r++) {
      for (int c = boxCol; c < boxCol + 3; c++) {
        if ((r != row || c != col) && _board.current[r][c] == value)
          return false;
      }
    }
    return true;
  }

  Set<String> get _displayInvalidCells {
    if (!widget.highlightMistakes) return const {};

    if (_solution != null) {
      final invalid = <String>{};
      for (int r = 0; r < 9; r++) {
        for (int c = 0; c < 9; c++) {
          if (_board.original[r][c] == 0 &&
              _board.current[r][c] != 0 &&
              _board.current[r][c] != _solution![r][c]) {
            invalid.add(_cellKey(r, c));
          }
        }
      }
      return invalid;
    }

    // No solution available: flag every user-placed cell that duplicates a value
    // in the same row, column, or 3x3 box.
    final conflicts = <String>{};

    for (int r = 0; r < 9; r++) {
      final seen = <int, List<int>>{};
      for (int c = 0; c < 9; c++) {
        final v = _board.current[r][c];
        if (v != 0) seen.putIfAbsent(v, () => []).add(c);
      }
      for (final cols in seen.values) {
        if (cols.length > 1) {
          for (final c in cols) {
            if (!_board.isCellLocked(r, c)) conflicts.add(_cellKey(r, c));
          }
        }
      }
    }

    for (int c = 0; c < 9; c++) {
      final seen = <int, List<int>>{};
      for (int r = 0; r < 9; r++) {
        final v = _board.current[r][c];
        if (v != 0) seen.putIfAbsent(v, () => []).add(r);
      }
      for (final rows in seen.values) {
        if (rows.length > 1) {
          for (final r in rows) {
            if (!_board.isCellLocked(r, c)) conflicts.add(_cellKey(r, c));
          }
        }
      }
    }

    for (int boxR = 0; boxR < 3; boxR++) {
      for (int boxC = 0; boxC < 3; boxC++) {
        final seen = <int, List<int>>{};
        for (int r = boxR * 3; r < boxR * 3 + 3; r++) {
          for (int c = boxC * 3; c < boxC * 3 + 3; c++) {
            final v = _board.current[r][c];
            if (v != 0) seen.putIfAbsent(v, () => []).add(r * 9 + c);
          }
        }
        for (final encoded in seen.values) {
          if (encoded.length > 1) {
            for (final e in encoded) {
              final r = e ~/ 9, c = e % 9;
              if (!_board.isCellLocked(r, c)) conflicts.add(_cellKey(r, c));
            }
          }
        }
      }
    }

    return conflicts;
  }

  double get _accuracyPercent {
    final totalActions = _filledFillableCells + _mistakes;
    if (totalActions <= 0) return 100;
    return ((_filledFillableCells / totalActions) * 100).clamp(0, 100);
  }

  Future<void> _openResultScreen({
    required bool won,
    bool allowContinueOnClose = false,
  }) async {
    if (!mounted) return;

    final ratingDelta = _lastRatingDelta;
    Analytics.capture('match_result', props: {
      'won': won,
      'mode': _isMultiplayer ? 'ranked' : _difficulty,
      'rating_delta': ratingDelta,
      'duration_seconds': _elapsedSeconds,
      'mistakes': _mistakes,
    });
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VictoryScreen(
        won: won,
        multiplayer: _isMultiplayer,
        allowClose: allowContinueOnClose,
        playerName: _playerName,
        playerUserId: widget.currentUserId,
        playerRating: _playerRating,
        ratingDelta: ratingDelta,
        timeText: _formatTime(),
        accuracy: _accuracyPercent,
        mistakes: _mistakes,
        progress: _playerProgressPercent,
        difficulty: _difficulty,
      ),
    );

    if (!mounted) return;

    if (result == 'close' && allowContinueOnClose) {
      final continuePlaying = await showDialog<bool>(
        context: context,
        builder: (context) {
          return Dialog(
            backgroundColor: Colors.white,
            insetPadding: const EdgeInsets.symmetric(horizontal: 32),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.grid_view_rounded,
                        color: AppColors.primary, size: 28),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Keep Playing?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The match is over. Finish this board at your own pace, or head back to the lobby.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: AppColors.outlineVariant, width: 1.5),
                              foregroundColor: AppColors.onSurface,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text(
                              'Go Back',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text(
                              'Keep Solving',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (!mounted) return;

      if (continuePlaying == true) {
        setState(() {
          _postMatchPracticeMode = true;
          _showBackAfterMatch = true;
          _gameEnded = false;
          _awaitingFinish = false;
        });
        return;
      }
    }

    if (result == 'rematch') {
      await _startNewGameFromModal();
      return;
    }

    if (_isMultiplayer) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(
          {'rating': _playerRating, 'ratingDelta': _lastRatingDelta},
        );
      }
      return;
    }

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(
        {'rating': _playerRating, 'ratingDelta': _lastRatingDelta},
      );
    }
  }

  Future<void> _startNewGameFromModal() async {
    try {
      if (_isMultiplayer && widget.currentUserId != null) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop('rematch');
        }
        return;
      }

      final session = await GameApiService.newGame(_difficulty);
      if (!mounted) return;
      setState(() {
        _loadSession(session);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start a new game')),
      );
    }
  }

  void _reportProgress({bool completed = false}) {
    if (_postMatchPracticeMode) return;
    if (_gameId == null) return;

    if (_isMultiplayer && widget.currentUserId != null) {
      _socketService.sendProgressUpdate(
        userId: widget.currentUserId!,
        gameId: _gameId!,
        filledCells: _filledFillableCells,
        mistakes: _mistakes,
        completed: completed,
        board: _board.cloneCurrent(),
      );
      return;
    }

    GameApiService.updateGameProgress(
      gameId: _gameId!,
      filledCells: _filledFillableCells,
      mistakes: _mistakes,
    );
  }

  void _onCellTap(int row, int col) {
    setState(() {
      _selectedRow = row;
      _selectedCol = col;
    });
  }

  Future<void> _onNumberInput(int number) async {
    if (_selectedRow == null || _selectedCol == null) return;
    if (_gameEnded || _awaitingFinish) return;
    if (_board.isCellLocked(_selectedRow!, _selectedCol!)) return;

    final row = _selectedRow!;
    final col = _selectedCol!;

    if (_noteMode) {
      final key = _noteKey(row, col);
      setState(() {
        final notes = _cellNotes[key] ?? <int>{};
        if (notes.contains(number)) {
          notes.remove(number);
        } else {
          notes.add(number);
        }
        if (notes.isEmpty) {
          _cellNotes.remove(key);
        } else {
          _cellNotes[key] = notes;
        }
      });
      return;
    }

    final previous = _board.current[row][col];
    if (previous == number) return;

    final isWrong = _solution != null
        ? number != _solution![row][col]
        : !_isValidPlacement(row, col, number);

    setState(() {
      _moveHistory.add(_Move(row, col, previous, isWrong));
      _board.setCell(row, col, number);
      if (isWrong) {
        _mistakes += 1;
      }
      _cellNotes.remove(_noteKey(row, col));
    });

    _reportProgress();
    _persistSnapshot();

    if (!_isMultiplayer && !_gameEnded && _mistakes >= 3) {
      setState(() {
        _gameEnded = true;
        _lost = true;
      });
      await _openResultScreen(won: false, allowContinueOnClose: true);
      return;
    }

    if (!_gameEnded && _isSolvedLocally()) {
      if (_isMultiplayer) {
        setState(() {
          _awaitingFinish = true;
        });
        _reportProgress(completed: true);
        // Defensive: the server now broadcasts the result instantly, but if a
        // network stall swallows game_end, don't trap the player on the
        // "verifying" spinner forever.
        _finishTimeout?.cancel();
        _finishTimeout = Timer(const Duration(seconds: 5), () {
          if (!mounted || _gameEnded) return;
          setState(() => _awaitingFinish = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Still confirming your win — tap the last cell again.')),
          );
        });
        return;
      }

      setState(() {
        _gameEnded = true;
        _lost = false;
      });
      await _openResultScreen(won: true, allowContinueOnClose: true);
    }
  }

  void _onUndo() {
    if (_moveHistory.isEmpty || _gameEnded || _awaitingFinish) return;
    final last = _moveHistory.removeLast();
    setState(() {
      _board.setCell(last.row, last.col, last.prevValue);
      _selectedRow = last.row;
      _selectedCol = last.col;
      // Undoing a wrong entry should give the mistake back, not leave the count
      // permanently inflated.
      if (last.wasInvalid) {
        _mistakes = (_mistakes - 1).clamp(0, 99);
      }
    });

    _reportProgress();
    _persistSnapshot();
  }

  void _onErase() {
    if (_gameEnded) return;

    setState(() {
      for (int row = 0; row < 9; row++) {
        for (int col = 0; col < 9; col++) {
          if (!_board.isCellLocked(row, col)) {
            _board.setCell(row, col, 0);
          }
        }
      }
      _moveHistory.clear();
      _cellNotes.clear();
    });

    _reportProgress();
  }

  String _formatTime() {
    final minutes = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _surrender() {
    Analytics.capture('match_surrendered', props: {
      'mode': _isMultiplayer ? 'ranked' : _difficulty,
      'elapsed_seconds': _elapsedSeconds,
    });

    if (!_isMultiplayer || _gameId == null) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    // Tell the server immediately so it finalizes (and updates ratings) right
    // away instead of waiting out the disconnect-reconnect grace window. The
    // existing gameEndStream listener picks up the resulting game_end and
    // shows the result screen with the new rating already applied.
    setState(() => _awaitingFinish = true);
    _socketService.surrender(_gameId!);

    _finishTimeout?.cancel();
    _finishTimeout = Timer(const Duration(seconds: 5), () {
      if (!mounted || _gameEnded) return;
      setState(() => _awaitingFinish = false);
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  void _showGameMenu() {
    // Single centered window: title, a hide-ratings toggle, a destructive
    // Surrender action, and a resume button. Tapping the scrim closes it.
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: AppColors.surfaceContainerLowest,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text(
                      'Game Options',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => Navigator.of(dialogContext).pop(),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: AppColors.surfaceContainerHigh,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            size: 18, color: AppColors.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                // Hide ratings toggle row.
                StatefulBuilder(
                  builder: (ctx, setLocal) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.visibility_off_outlined,
                            size: 20, color: AppColors.onSurfaceVariant),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Hide ratings during game',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurface,
                            ),
                          ),
                        ),
                        Switch(
                          value: _hideRatings,
                          activeColor: Colors.white,
                          activeTrackColor: AppColors.primary,
                          onChanged: (v) {
                            setLocal(() {});
                            setState(() => _hideRatings = v);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      _surrender();
                    },
                    icon: const Icon(Icons.flag_outlined, size: 20),
                    label: const Text(
                      'Surrender Match',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 52,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.onSurface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text(
                      'Resume Game',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Colors.white;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
          child: Column(
            children: [
              _TopStatusRow(
                timeText: widget.timerEnabled ? _formatTime() : '--:--',
                onMenuTap: _showGameMenu,
                showBackButton: _showBackAfterMatch,
                onBackTap: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
              ),
              const SizedBox(height: 10),
              _VersusHeader(
                playerName: _playerName,
                opponentName: _opponentName,
                playerUserId: widget.currentUserId,
                opponentUserId: _opponentId,
                playerRating: _playerRating,
                opponentRating: _opponentRating,
                showRatings: !_hideRatings,
              ),
              const SizedBox(height: 10),
              _ProgressPanel(
                playerProgress: _playerProgressPercent,
                opponentProgress: _opponentProgressPercent,
                mistakes: _mistakes,
                opponentMistakes: _opponentMistakes,
              ),
              if (_awaitingFinish)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Confirming your win…',
                        style: TextStyle(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Expanded(
                flex: 5,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x15000000),
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: SudokuGrid(
                        board: _board,
                        selectedRow: _selectedRow,
                        selectedCol: _selectedCol,
                        onCellTap: _onCellTap,
                        invalidCells: _displayInvalidCells,
                        notes: _cellNotes,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _ActionButtonsRow(
                onUndo: _onUndo,
                onErase: _onErase,
                noteMode: _noteMode,
                onToggleNotes: () {
                  setState(() {
                    _noteMode = !_noteMode;
                  });
                },
              ),
              const SizedBox(height: 10),
              _NumberInputRow(onNumberInput: _onNumberInput),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopStatusRow extends StatelessWidget {
  final String timeText;
  final VoidCallback onMenuTap;
  final bool showBackButton;
  final VoidCallback? onBackTap;

  const _TopStatusRow({
    required this.timeText,
    required this.onMenuTap,
    this.showBackButton = false,
    this.onBackTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showBackButton)
          IconButton(
            onPressed: onBackTap,
            icon: const Icon(Icons.arrow_back, color: AppColors.primary),
          )
        else
          const SizedBox(width: 48),
        Expanded(
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_outlined,
                    size: 20, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  timeText,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          onPressed: onMenuTap,
          icon: const Icon(Icons.settings, color: AppColors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _VersusHeader extends StatelessWidget {
  final String playerName;
  final String opponentName;
  final String? playerUserId;
  final String? opponentUserId;
  final int playerRating;
  final int opponentRating;
  final bool showRatings;

  const _VersusHeader({
    required this.playerName,
    required this.opponentName,
    this.playerUserId,
    this.opponentUserId,
    required this.playerRating,
    required this.opponentRating,
    this.showRatings = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          UserAvatar(
            userId: playerUserId ?? 'player',
            name: playerName,
            size: 32,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                if (showRatings)
                  Text(
                    '$playerRating',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '/',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 28,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  opponentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                if (showRatings)
                  Text(
                    '$opponentRating',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          UserAvatar(
            userId: opponentUserId ?? 'opponent',
            name: opponentName,
            size: 32,
          ),
        ],
      ),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  final int playerProgress;
  final int opponentProgress;
  final int mistakes;
  final int opponentMistakes;

  const _ProgressPanel({
    required this.playerProgress,
    required this.opponentProgress,
    required this.mistakes,
    required this.opponentMistakes,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'PROGRESS',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  color: AppColors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'OPPONENT',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  color: AppColors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '$playerProgress%',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'M:$mistakes',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'M:$opponentMistakes',
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$opponentProgress%',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          _HeadToHeadProgressBar(
            playerProgress: playerProgress,
            opponentProgress: opponentProgress,
          ),
        ],
      ),
    );
  }
}

class _HeadToHeadProgressBar extends StatelessWidget {
  final int playerProgress;
  final int opponentProgress;

  const _HeadToHeadProgressBar({
    required this.playerProgress,
    required this.opponentProgress,
  });

  @override
  Widget build(BuildContext context) {
    // Two independent absolute meters (each 0-100% of its own fill). A previous
    // version drew relative shares (player / (player + opponent)), which made a
    // bar shrink when the other side advanced and froze at 50/50 when tied.
    return Column(
      children: [
        _AbsoluteBar(
          percent: playerProgress,
          color: AppColors.primary,
        ),
        const SizedBox(height: 6),
        _AbsoluteBar(
          percent: opponentProgress,
          color: AppColors.error,
        ),
      ],
    );
  }
}

/// A single progress track that fills left-to-right by an absolute [percent]
/// (0-100), animating smoothly to each new value.
class _AbsoluteBar extends StatelessWidget {
  final int percent;
  final Color color;

  const _AbsoluteBar({required this.percent, required this.color});

  @override
  Widget build(BuildContext context) {
    final fraction = (percent.clamp(0, 100)) / 100.0;
    return Container(
      height: 9,
      decoration: BoxDecoration(
        color: AppColors.outlineVariant,
        borderRadius: BorderRadius.circular(999),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: fraction),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            builder: (context, value, _) => FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(color: color),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButtonsRow extends StatelessWidget {
  final VoidCallback onUndo;
  final VoidCallback onErase;
  final bool noteMode;
  final VoidCallback onToggleNotes;

  const _ActionButtonsRow({
    required this.onUndo,
    required this.onErase,
    required this.noteMode,
    required this.onToggleNotes,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _GameActionButton(
          icon: Icons.undo_rounded,
          label: 'UNDO',
          onTap: onUndo,
        ),
        _GameActionButton(
          icon: Icons.close_rounded,
          label: 'ERASE',
          onTap: onErase,
        ),
        _GameActionButton(
          icon: Icons.edit,
          label: noteMode ? 'ACTIVE' : 'NOTE',
          badge: noteMode ? 'ON' : 'OFF',
          highlighted: noteMode,
          onTap: onToggleNotes,
        ),
      ],
    );
  }
}

class _Move {
  final int row;
  final int col;
  final int prevValue;
  final bool wasInvalid;

  _Move(this.row, this.col, this.prevValue, this.wasInvalid);
}

class _GameActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? badge;
  final bool highlighted;
  final VoidCallback? onTap;

  const _GameActionButton({
    required this.icon,
    required this.label,
    this.badge,
    this.highlighted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 58,
              height: 42,
              decoration: BoxDecoration(
                color: highlighted
                    ? AppColors.primary
                    : AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Icon(
                      icon,
                      size: 22,
                      color:
                          highlighted ? Colors.white : AppColors.onSurfaceVariant,
                    ),
                  ),
                  if (badge != null)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: highlighted
                              ? Colors.white
                              : AppColors.outlineVariant,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badge!,
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: highlighted
                                ? AppColors.primary
                                : AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: highlighted
                    ? AppColors.primary
                    : AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberInputRow extends StatelessWidget {
  final Future<void> Function(int) onNumberInput;

  const _NumberInputRow({required this.onNumberInput});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Row(
        children: List.generate(9, (i) {
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                onNumberInput(i + 1);
              },
              child: Container(
                height: 48,
                alignment: Alignment.center,
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 34,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
