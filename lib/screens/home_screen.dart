import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_session.dart';
import '../services/multiplayer_socket_service.dart';
import 'game_screen.dart';

class HomeScreen extends StatefulWidget {
  final bool highlightMistakes;
  final bool timerEnabled;

  const HomeScreen({
    Key? key,
    required this.highlightMistakes,
    required this.timerEnabled,
  }) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MultiplayerSocketService _socketService =
      MultiplayerSocketService.instance;
  final ValueNotifier<int> _queueSecondsNotifier = ValueNotifier<int>(0);
  StreamSubscription<Map<String, dynamic>>? _matchSub;
  StreamSubscription<Map<String, dynamic>>? _reconnectRequiredSub;
  Timer? _queueTimer;
  int _queueSeconds = 0;
  bool _queueDialogOpen = false;

  @override
  void dispose() {
    _matchSub?.cancel();
    _reconnectRequiredSub?.cancel();
    _queueTimer?.cancel();
    _queueSecondsNotifier.dispose();
    super.dispose();
  }

  Future<String> _getOrCreateUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('local_user_id');
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final randomPart = Random().nextInt(999999).toString().padLeft(6, '0');
    final id = 'user_${DateTime.now().millisecondsSinceEpoch}_$randomPart';
    await prefs.setString('local_user_id', id);
    return id;
  }

  String _formatQueueTime(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _startMatchmaking() async {
    try {
      bool matched = false;
      final userId = await _getOrCreateUserId();
      await _socketService.connect(userId);

      await _matchSub?.cancel();
      await _reconnectRequiredSub?.cancel();
      _matchSub = _socketService.matchFoundStream.listen((payload) async {
        if (!_queueDialogOpen || !mounted) return;

        final session = GameSession.fromMatchFound(payload);
        matched = true;
        _queueDialogOpen = false;
        _queueTimer?.cancel();

        Navigator.of(context, rootNavigator: true).pop();

        final result = await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GameScreen(
              initialSession: session,
              highlightMistakes: widget.highlightMistakes,
              timerEnabled: widget.timerEnabled,
              currentUserId: userId,
              multiplayerEnabled: true,
            ),
          ),
        );

        if (mounted && result == 'rematch') {
          await _startMatchmaking();
        }
      });

      _reconnectRequiredSub =
          _socketService.reconnectRequiredStream.listen((payload) async {
        if (!mounted) return;

        _queueDialogOpen = false;
        _queueTimer?.cancel();

        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }

        final shouldResume = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Resume Match'),
              content: const Text(
                  'You already have an active match. Resume it now?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('No'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Resume'),
                ),
              ],
            );
          },
        );

        if (shouldResume != true) {
          _socketService.disconnect();
          return;
        }

        final session = GameSession.fromMatchFound(payload);
        final result = await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GameScreen(
              initialSession: session,
              highlightMistakes: widget.highlightMistakes,
              timerEnabled: widget.timerEnabled,
              currentUserId: userId,
              multiplayerEnabled: true,
            ),
          ),
        );

        if (mounted && result == 'rematch') {
          await _startMatchmaking();
        }
      });

      _queueSeconds = 0;
      _queueSecondsNotifier.value = 0;
      _queueDialogOpen = true;
      _queueTimer?.cancel();
      _queueTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_queueDialogOpen) return;
        _queueSeconds += 1;
        _queueSecondsNotifier.value = _queueSeconds;
      });

      _socketService.joinQueue(userId);

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Looking for an opponent',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  ValueListenableBuilder<int>(
                    valueListenable: _queueSecondsNotifier,
                    builder: (context, value, _) {
                      return Text(
                        _formatQueueTime(value),
                        style: const TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w700),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  const LinearProgressIndicator(minHeight: 6),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        _queueDialogOpen = false;
                        _queueTimer?.cancel();
                        Navigator.of(dialogContext).pop();
                      },
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      _queueDialogOpen = false;
      _queueTimer?.cancel();
      if (!matched) {
        _socketService.disconnect();
      }
    } catch (_) {
      _queueDialogOpen = false;
      _queueTimer?.cancel();
      _socketService.disconnect();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Could not connect to matchmaking server on port 4000')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 240,
              height: 58,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _startMatchmaking,
                child: const Text(
                  'Play',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
