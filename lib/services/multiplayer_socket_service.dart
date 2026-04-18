import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

class MultiplayerSocketService {
  MultiplayerSocketService._();

  static final MultiplayerSocketService instance = MultiplayerSocketService._();

  static const String _socketUrl = 'http://192.168.0.103:4000';

  io.Socket? _socket;
  String? _currentUserId;

  final StreamController<Map<String, dynamic>> _matchFoundController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _progressUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _gameEndController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _ratingUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _gameStateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _opponentDisconnectedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _opponentReconnectedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _progressRejectedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _reconnectRequiredController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _gameStateErrorController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<bool> _connectedController =
      StreamController<bool>.broadcast();

  Stream<Map<String, dynamic>> get matchFoundStream =>
      _matchFoundController.stream;
  Stream<Map<String, dynamic>> get progressUpdateStream =>
      _progressUpdateController.stream;
  Stream<Map<String, dynamic>> get gameEndStream => _gameEndController.stream;
  Stream<Map<String, dynamic>> get ratingUpdateStream =>
      _ratingUpdateController.stream;
  Stream<Map<String, dynamic>> get gameStateStream =>
      _gameStateController.stream;
  Stream<Map<String, dynamic>> get opponentDisconnectedStream =>
      _opponentDisconnectedController.stream;
  Stream<Map<String, dynamic>> get opponentReconnectedStream =>
      _opponentReconnectedController.stream;
  Stream<Map<String, dynamic>> get progressRejectedStream =>
      _progressRejectedController.stream;
  Stream<Map<String, dynamic>> get reconnectRequiredStream =>
      _reconnectRequiredController.stream;
  Stream<Map<String, dynamic>> get gameStateErrorStream =>
      _gameStateErrorController.stream;
  Stream<bool> get connectionStream => _connectedController.stream;

  bool get isConnected => _socket?.connected == true;

  Future<void> connect(String userId) async {
    _currentUserId = userId;

    if (_socket != null && _socket!.connected) {
      return;
    }

    _socket = io.io(
      _socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(20)
          .setReconnectionDelay(500)
          .build(),
    );

    _socket!.onConnect((_) {
      _connectedController.add(true);
    });

    _socket!.onDisconnect((_) {
      _connectedController.add(false);
    });

    _socket!.on('match_found', (payload) {
      _matchFoundController.add(_toMap(payload));
    });

    _socket!.on('progress_update', (payload) {
      _progressUpdateController.add(_toMap(payload));
    });

    _socket!.on('game_end', (payload) {
      _gameEndController.add(_toMap(payload));
    });

    _socket!.on('rating_update', (payload) {
      _ratingUpdateController.add(_toMap(payload));
    });

    _socket!.on('game_state', (payload) {
      _gameStateController.add(_toMap(payload));
    });

    _socket!.on('opponent_disconnected', (payload) {
      _opponentDisconnectedController.add(_toMap(payload));
    });

    _socket!.on('opponent_reconnected', (payload) {
      _opponentReconnectedController.add(_toMap(payload));
    });

    _socket!.on('progress_rejected', (payload) {
      _progressRejectedController.add(_toMap(payload));
    });

    _socket!.on('reconnect_required', (payload) {
      _reconnectRequiredController.add(_toMap(payload));
    });

    _socket!.on('game_state_error', (payload) {
      _gameStateErrorController.add(_toMap(payload));
    });

    _socket!.connect();

    await _waitForConnect();
  }

  Future<void> _waitForConnect() async {
    if (_socket?.connected == true) return;

    final completer = Completer<void>();
    late StreamSubscription<bool> sub;
    sub = connectionStream.listen((connected) {
      if (connected && !completer.isCompleted) {
        completer.complete();
      }
    });

    await completer.future.timeout(const Duration(seconds: 8));
    await sub.cancel();
  }

  void joinQueue(String userId) {
    _currentUserId = userId;
    _socket?.emit('join_queue', {
      'userId': userId,
    });
  }

  void reconnectGame(String userId, String gameId) {
    _currentUserId = userId;
    _socket?.emit('reconnect_game', {
      'userId': userId,
      'gameId': gameId,
    });
  }

  void sendProgressUpdate({
    required String userId,
    required String gameId,
    required int filledCells,
    required int mistakes,
    required bool completed,
    List<List<int>>? board,
  }) {
    _socket?.emit('progress_update', {
      'userId': userId,
      'gameId': gameId,
      'filledCells': filledCells,
      'mistakes': mistakes,
      'completed': completed,
      if (board != null) 'board': board,
    });
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  Map<String, dynamic> _toMap(dynamic payload) {
    if (payload is Map<String, dynamic>) return payload;
    if (payload is Map) {
      return payload.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }
}
