import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_colors.dart';
import '../models/game_session.dart';
import '../services/game_api_service.dart';
import '../services/multiplayer_socket_service.dart';
import 'game_screen.dart';

extension _StringCapitalize on String {
  String get capitalized =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
}

class HomeScreen extends StatefulWidget {
  final bool highlightMistakes;
  final bool timerEnabled;
  final VoidCallback? onSettingsPressed;

  const HomeScreen({
    super.key,
    required this.highlightMistakes,
    required this.timerEnabled,
    this.onSettingsPressed,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  // Matchmaking
  final MultiplayerSocketService _socketService =
      MultiplayerSocketService.instance;
  final ValueNotifier<int> _queueSecondsNotifier = ValueNotifier<int>(0);
  StreamSubscription<Map<String, dynamic>>? _matchSub;
  StreamSubscription<Map<String, dynamic>>? _reconnectRequiredSub;
  Timer? _queueTimer;
  int _queueSeconds = 0;
  bool _queueDialogOpen = false;

  // Profile
  bool _profileLoading = true;
  int _rating = 1200;
  int _ratingDelta = 0;
  String _userId = '';
  List<Map<String, dynamic>> _matchHistory = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _matchSub?.cancel();
    _reconnectRequiredSub?.cancel();
    _queueTimer?.cancel();
    _queueSecondsNotifier.dispose();
    super.dispose();
  }

  // ─── Profile Loading ───────────────────────────────────────────────────────

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() => _profileLoading = true);

    final userId = await _getOrCreateUserId();
    final profile = await GameApiService.getUserProfile(userId);
    final history = await GameApiService.getUserMatchHistory(userId);

    if (!mounted) return;

    int delta = 0;
    if (history.isNotEmpty) {
      delta = (history.first['rating_delta'] as num?)?.toInt() ?? 0;
    }

    setState(() {
      _userId = userId;
      _rating = (profile?['rating'] as num?)?.toInt() ?? 1200;
      _ratingDelta = delta;
      _matchHistory = history.take(3).toList();
      _profileLoading = false;
    });
  }

  // ─── UUID Helpers ──────────────────────────────────────────────────────────

  Future<String> _getOrCreateUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('local_user_id');
    if (existing != null && _uuidPattern.hasMatch(existing)) return existing;
    final id = _generateUuidV4();
    await prefs.setString('local_user_id', id);
    return id;
  }

  String _generateUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String toHex(int v) => v.toRadixString(16).padLeft(2, '0');
    final hex = bytes.map(toHex).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  // ─── Matchmaking ───────────────────────────────────────────────────────────

  String _formatQueueTime(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _startMatchmaking() async {
    try {
      bool matched = false;
      final userId =
          _userId.isNotEmpty ? _userId : await _getOrCreateUserId();
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
        } else {
          _loadProfile();
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
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: AppColors.surfaceContainerLowest,
            title: const Text('Resume Match',
                style: TextStyle(fontWeight: FontWeight.bold)),
            content: const Text('You have an active match. Resume it?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('No')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Resume'),
              ),
            ],
          ),
        );

        if (shouldResume != true) {
          _socketService.disconnect();
          return;
        }

        final session = GameSession.fromMatchFound(payload);
        if (!mounted) return;
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

        if (mounted && result == 'rematch') await _startMatchmaking();
      });

      _queueSeconds = 0;
      _queueSecondsNotifier.value = 0;
      _queueDialogOpen = true;
      _queueTimer?.cancel();
      _queueTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_queueDialogOpen) return;
        _queueSeconds++;
        _queueSecondsNotifier.value = _queueSeconds;
      });

      _socketService.joinQueue(userId);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Dialog(
          backgroundColor: AppColors.surfaceContainerLowest,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Finding Opponent',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Searching for a worthy challenger',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                ValueListenableBuilder<int>(
                  valueListenable: _queueSecondsNotifier,
                  builder: (_, value, __) => Text(
                    _formatQueueTime(value),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const LinearProgressIndicator(
                  minHeight: 4,
                  backgroundColor: AppColors.surfaceContainerHigh,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.onSurfaceVariant,
                      side: const BorderSide(color: AppColors.outlineVariant),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
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
        ),
      );

      _queueDialogOpen = false;
      _queueTimer?.cancel();
      if (!matched) _socketService.disconnect();
    } catch (_) {
      _queueDialogOpen = false;
      _queueTimer?.cancel();
      _socketService.disconnect();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not connect to matchmaking server on port 4000'),
        ),
      );
    }
  }

  // ─── UI Builders ───────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primaryFixed, width: 2),
              color: AppColors.surfaceContainerHigh,
            ),
            child: const Icon(Icons.person, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          _profileLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                )
              : Text(
                  _rating.toString(),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Color(0xFF44474E)),
            onPressed: widget.onSettingsPressed,
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ELO card
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CURRENT ELO',
                  style: TextStyle(
                    color: AppColors.outline,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _profileLoading ? '—' : _rating.toString(),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    if (!_profileLoading && _ratingDelta != 0) ...[
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(
                              _ratingDelta > 0
                                  ? Icons.trending_up
                                  : Icons.trending_down,
                              color: _ratingDelta > 0
                                  ? AppColors.tertiaryContainer
                                  : AppColors.error,
                              size: 15,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${_ratingDelta > 0 ? '+' : ''}$_ratingDelta',
                              style: TextStyle(
                                color: _ratingDelta > 0
                                    ? AppColors.tertiaryContainer
                                    : AppColors.error,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  "Maintain your streak to reach Master's Tier.",
                  style: TextStyle(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 12),

        // Play Now card
        Expanded(
          child: GestureDetector(
            onTap: _startMatchmaking,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.primaryContainer],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        'New Match',
                        style: TextStyle(
                          color: AppColors.onPrimaryContainer,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Icon(
                        Icons.sports_esports,
                        color: AppColors.onPrimaryContainer,
                        size: 28,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'PLAY NOW',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyChallengeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: const [
            Text(
              'Daily Challenge',
              style: TextStyle(
                color: AppColors.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'Expires in 14h 22m',
              style: TextStyle(color: AppColors.outline, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.tertiaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'EXPERT',
                            style: TextStyle(
                              color: AppColors.onTertiaryContainer,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Symmetry Pattern',
                          style: TextStyle(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "The Archon's Paradox",
                      style: TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: const LinearProgressIndicator(
                        value: 0.65,
                        minHeight: 4,
                        backgroundColor: AppColors.surfaceVariant,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '65% GLOBAL FAIL RATE',
                      style: TextStyle(
                        color: AppColors.outline,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: const Icon(
                  Icons.grid_on,
                  color: Color(0x330040A1),
                  size: 40,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '--:--';
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildMatchItem(Map<String, dynamic> match, {required bool isFirst}) {
    final isWin = match['outcome']?.toString() == 'win' ||
        match['won'] == true;
    final opponent = match['opponent_name']?.toString() ??
        match['opponent_username']?.toString() ??
        'Opponent';
    final duration = (match['duration'] as num?)?.toInt();
    final difficulty =
        (match['difficulty']?.toString() ?? 'normal').capitalized;
    final delta = (match['rating_delta'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 0 : 20),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isWin
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isWin ? Icons.check_circle : Icons.timer,
              color: isWin ? AppColors.primary : AppColors.outline,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isWin ? 'Victory vs $opponent' : 'Timed Out',
                  style: const TextStyle(
                    color: AppColors.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$difficulty • ${_formatDuration(duration)} min',
                  style: const TextStyle(
                    color: AppColors.outline,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                delta == 0
                    ? '—'
                    : (delta > 0 ? '+$delta' : '$delta'),
                style: TextStyle(
                  color:
                      delta >= 0 ? AppColors.tertiaryContainer : AppColors.error,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'Points',
                style: TextStyle(color: AppColors.outline, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent History',
          style: TextStyle(
            color: AppColors.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        if (_profileLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2),
            ),
          )
        else if (_matchHistory.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No matches yet.\nPlay your first ranked game!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.outline,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
            ),
          )
        else
          ..._matchHistory.asMap().entries.map(
                (e) => _buildMatchItem(e.value, isFirst: e.key == 0),
              ),
      ],
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeroSection(),
                    const SizedBox(height: 32),
                    _buildDailyChallengeSection(),
                    const SizedBox(height: 32),
                    _buildRecentHistory(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
