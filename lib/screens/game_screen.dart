import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/sudoku_validator.dart';
import '../models/game_session.dart';
import '../models/sudoku_board.dart';
import '../services/game_api_service.dart';
import '../services/multiplayer_socket_service.dart';
import 'victory_screen.dart';
import '../widgets/sudoku_grid.dart';

class GameScreen extends StatefulWidget {
  final GameSession? initialSession;
  final bool highlightMistakes;
  final bool timerEnabled;
  final String? currentUserId;
  final bool multiplayerEnabled;

  const GameScreen({
    super.key,
    this.initialSession,
    required this.highlightMistakes,
    required this.timerEnabled,
    this.currentUserId,
    this.multiplayerEnabled = false,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final MultiplayerSocketService _socketService =
      MultiplayerSocketService.instance;

  late SudokuBoard _board;
  List<List<int>>? _solution;
  String? _gameId;
  String _difficulty = 'ranked';
  int? _selectedRow;
  int? _selectedCol;
  final List<_Move> _moveHistory = [];
  final Set<String> _invalidCells = {};
  final List<StreamSubscription> _subs = [];

  Timer? _timer;
  int _elapsedSeconds = 0;
  int _mistakes = 0;
  bool _gameEnded = false;
  bool _lost = false;
  bool _awaitingFinish = false;
  bool _gameStateErrorShown = false;
  bool _noteMode = false;
  bool _postMatchPracticeMode = false;
  bool _showBackAfterMatch = false;

  final Map<String, Set<int>> _cellNotes = {};

  String _playerName = 'You';
  String _opponentName = 'Opponent';
  int _playerRating = 1200;
  int _opponentRating = 1200;
  int _opponentProgressPercent = 0;
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
    _loadSession(widget.initialSession);
    _startTimerIfNeeded();
    if (_isMultiplayer) {
      _bindMultiplayerEvents();
      if (widget.currentUserId != null && _gameId != null) {
        _socketService.reconnectGame(widget.currentUserId!, _gameId!);
      }
    }
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
    _timer?.cancel();
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
      if (ratings is! Map) return;

      setState(() {
        final me = widget.currentUserId;
        if (me != null && ratings[me] is num) {
          _playerRating = (ratings[me] as num).toInt();
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
      _invalidCells.clear();
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
    _invalidCells.clear();
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
        if (_board.original[row][col] == 0 && _board.current[row][col] != 0) {
          count++;
        }
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

    final previousRating = _playerRating - (won ? 20 : -10);
    final ratingDelta = _playerRating - previousRating;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VictoryScreen(
        won: won,
        multiplayer: _isMultiplayer,
        allowClose: allowContinueOnClose,
        playerName: _playerName,
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
          return AlertDialog(
            title: const Text('Result Closed'),
            content: const Text(
              'Do you want to keep solving this board locally, or go back?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Back'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Continue'),
              ),
            ],
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
        Navigator.of(context).pop();
      }
      return;
    }

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
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
    final wasInvalid = _invalidCells.contains(_cellKey(row, col));
    if (previous == number) return;

    final isWrong = _solution != null
        ? number != _solution![row][col]
        : !_isValidPlacement(row, col, number);

    setState(() {
      _moveHistory.add(_Move(row, col, previous, wasInvalid));
      _board.setCell(row, col, number);
      if (isWrong) {
        _mistakes += 1;
        if (widget.highlightMistakes) {
          _invalidCells.add(_cellKey(row, col));
        }
      } else {
        _invalidCells.remove(_cellKey(row, col));
      }
      _cellNotes.remove(_noteKey(row, col));
    });

    _reportProgress();

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
    if (_moveHistory.isEmpty || _gameEnded) return;
    final last = _moveHistory.removeLast();
    setState(() {
      _board.setCell(last.row, last.col, last.prevValue);
      _selectedRow = last.row;
      _selectedCol = last.col;
      if (last.wasInvalid) {
        _invalidCells.add(_cellKey(last.row, last.col));
      } else {
        _invalidCells.remove(_cellKey(last.row, last.col));
      }
    });

    _reportProgress();
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
      _invalidCells.clear();
      _cellNotes.clear();
    });

    _reportProgress();
  }

  Future<void> _onHint() async {
    if (_isMultiplayer) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Hint is disabled in multiplayer matches.')),
      );
      return;
    }

    if (_gameId == null) return;
    final hint =
        await GameApiService.hint(board: _board.current, gameId: _gameId!);
    if (!mounted || hint == null) return;

    final row = hint['row']!;
    final col = hint['col']!;
    final value = hint['value']!;
    if (_board.isCellLocked(row, col)) return;

    setState(() {
      _moveHistory.add(
        _Move(row, col, _board.current[row][col],
            _invalidCells.contains(_cellKey(row, col))),
      );
      _board.setCell(row, col, value);
      _selectedRow = row;
      _selectedCol = col;
      _invalidCells.remove(_cellKey(row, col));
    });

    _reportProgress();

    if (!_gameEnded && _isSolvedLocally()) {
      setState(() {
        _gameEnded = true;
        _lost = false;
      });
      await _openResultScreen(won: true, allowContinueOnClose: true);
    }
  }

  String _formatTime() {
    final minutes = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _showGameMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.flag),
                title: const Text('Resume match'),
                onTap: () => Navigator.of(context).pop(),
              ),
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Exit to Home'),
                onTap: () {
                  Navigator.of(context).pop();
                  if (Navigator.of(this.context).canPop()) {
                    Navigator.of(this.context).pop();
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Colors.white;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
          child: Column(
            children: [
              _TopStatusRow(
                rating: _playerRating,
                timeText: widget.timerEnabled ? _formatTime() : '--:--',
                onMenuTap: _showGameMenu,
                showBackButton: _showBackAfterMatch,
                onBackTap: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
              ),
              const SizedBox(height: 12),
              _VersusHeader(
                playerName: _playerName,
                opponentName: _opponentName,
                playerRating: _playerRating,
                opponentRating: _opponentRating,
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
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Waiting for server verification...'),
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
                        invalidCells: _invalidCells,
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
                onHint: _onHint,
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
  final int rating;
  final String timeText;
  final VoidCallback onMenuTap;
  final bool showBackButton;
  final VoidCallback? onBackTap;

  const _TopStatusRow({
    required this.rating,
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
            icon: const Icon(Icons.arrow_back, color: Color(0xFF0E46A7)),
          )
        else
          const SizedBox(width: 6),
        const SizedBox(width: 6),
        const CircleAvatar(
          radius: 18,
          backgroundColor: Color(0xFFDEE5F2),
          child: Icon(Icons.person, color: Color(0xFF0E46A7)),
        ),
        const SizedBox(width: 8),
        Text(
          '$rating',
          style: const TextStyle(
            color: Color(0xFF0E46A7),
            fontSize: 30,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 10),
        const Icon(Icons.timer_outlined, size: 16, color: Color(0xFF64748B)),
        const SizedBox(width: 4),
        Text(
          timeText,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        IconButton(onPressed: onMenuTap, icon: const Icon(Icons.settings)),
      ],
    );
  }
}

class _VersusHeader extends StatelessWidget {
  final String playerName;
  final String opponentName;
  final int playerRating;
  final int opponentRating;

  const _VersusHeader({
    required this.playerName,
    required this.opponentName,
    required this.playerRating,
    required this.opponentRating,
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
          const CircleAvatar(
            radius: 16,
            backgroundColor: Color(0xFFE5E7EB),
            child: Icon(Icons.person, color: Color(0xFF0E46A7), size: 18),
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
                    color: Color(0xFF1F2937),
                  ),
                ),
                Text(
                  '$playerRating ELO',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF0E46A7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Text(
            'VS',
            style: TextStyle(
              color: Color(0xFF9CA3AF),
              fontWeight: FontWeight.w700,
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
                    color: Color(0xFF1F2937),
                  ),
                ),
                Text(
                  '$opponentRating ELO',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const CircleAvatar(
            radius: 16,
            backgroundColor: Color(0xFF0A0D14),
            child: Icon(Icons.person, color: Colors.white, size: 18),
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
            children: [
              const Text(
                'PROGRESS',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              const Text(
                'MATCH POINT',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  color: Color(0xFF0E46A7),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              const Text(
                'OPPONENT',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '$playerProgress%',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF10151E),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8EEFF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'M:$mistakes',
                  style: const TextStyle(
                    color: Color(0xFF0E46A7),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '$opponentProgress%',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF10151E),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE4E2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'M:$opponentMistakes',
                  style: const TextStyle(
                    color: Color(0xFFB42318),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
    final player = playerProgress.clamp(0, 100).toDouble();
    final opponent = opponentProgress.clamp(0, 100).toDouble();
    final total = (player + opponent) <= 0 ? 1.0 : (player + opponent);
    final playerShare = player / total;
    final opponentShare = opponent / total;

    return Container(
      height: 9,
      decoration: BoxDecoration(
        color: const Color(0xFFD3D9E4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final playerWidth = (width * playerShare).clamp(0.0, width);
            final opponentWidth = (width * opponentShare).clamp(0.0, width);

            return Stack(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: playerWidth,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2FA8FF),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: opponentWidth,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF5A5F),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ActionButtonsRow extends StatelessWidget {
  final VoidCallback onUndo;
  final VoidCallback onErase;
  final Future<void> Function() onHint;
  final bool noteMode;
  final VoidCallback onToggleNotes;

  const _ActionButtonsRow({
    required this.onUndo,
    required this.onErase,
    required this.onHint,
    required this.noteMode,
    required this.onToggleNotes,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
        _GameActionButton(
          icon: Icons.lightbulb_outline,
          label: 'HINT',
          onTap: () {
            onHint();
          },
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
                    ? const Color(0xFF0E53BE)
                    : const Color(0xFFE9EDF4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Icon(
                      icon,
                      size: 22,
                      color:
                          highlighted ? Colors.white : const Color(0xFF374151),
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
                              : const Color(0xFFD1D5DB),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badge!,
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: highlighted
                                ? const Color(0xFF0E53BE)
                                : const Color(0xFF6B7280),
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
                    ? const Color(0xFF0E53BE)
                    : const Color(0xFF6B7280),
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
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(9, (i) {
          return GestureDetector(
            onTap: () {
              onNumberInput(i + 1);
            },
            child: Container(
              width: 34,
              height: 44,
              alignment: Alignment.center,
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  fontSize: 36,
                  color: Color(0xFF0E53BE),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
