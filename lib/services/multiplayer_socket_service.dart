import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/api_config.dart';
import 'auth_service.dart';

class MultiplayerSocketService {
  MultiplayerSocketService._();

  static final MultiplayerSocketService instance = MultiplayerSocketService._();

  static final String _socketUrl = ApiConfig.socketUrl;

  io.Socket? _socket;

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
    if (_socket != null && _socket!.connected) {
      return;
    }

    // A leftover socket from a previous match (disposed manager, not connected)
    // can fail to reconnect — start clean.
    if (_socket != null) {
      _socket!.dispose();
      _socket = null;
    }

    // Send the Supabase access token so the backend can verify identity when
    // SUPABASE_JWT_SECRET is configured. Harmless when auth is disabled.
    final token = AuthService.instance.accessToken;
    final optionBuilder = io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .enableReconnection()
        .setReconnectionAttempts(20)
        .setReconnectionDelay(500);
    if (token != null) {
      optionBuilder.setAuth({'token': token});
    }

    _socket = io.io(_socketUrl, optionBuilder.build());

    // Completer wired BEFORE connect() so we can't miss the connect event. The
    // broadcast connectionStream doesn't buffer, so on a warm/instant reconnect
    // (e.g. tapping PLAY right after a match) a stream-based wait would drop the
    // event and time out — this avoids that race.
    final connectCompleter = Completer<void>();

    _socket!.onConnect((_) {
      _connectedController.add(true);
      if (!connectCompleter.isCompleted) connectCompleter.complete();
    });

    _socket!.onConnectError((err) {
      if (!connectCompleter.isCompleted) {
        connectCompleter.completeError(
          StateError('Socket connect error: $err'),
        );
      }
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

    if (_socket!.connected) return;
    await connectCompleter.future.timeout(const Duration(seconds: 8));
  }

  void joinQueue(String userId) {
    _socket?.emit('join_queue', {
      'userId': userId,
    });
  }

  void reconnectGame(String userId, String gameId) {
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
