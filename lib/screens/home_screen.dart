import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_colors.dart';
import '../config/api_config.dart';
import '../models/game_session.dart';
import '../services/active_game_store.dart';
import '../services/analytics_service.dart';
import '../services/game_api_service.dart';
import '../services/multiplayer_socket_service.dart';
import '../services/profile_cache_store.dart';
import '../widgets/page_transitions.dart';
import '../widgets/screen_header.dart';
import '../widgets/user_avatar.dart';
import 'game_screen.dart';

class HomeScreen extends StatefulWidget {
  final String userId;
  final bool highlightMistakes;
  final bool timerEnabled;
  final VoidCallback? onSettingsPressed;

  const HomeScreen({
    super.key,
    required this.userId,
    required this.highlightMistakes,
    required this.timerEnabled,
    this.onSettingsPressed,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Matchmaking
  final MultiplayerSocketService _socketService =
      MultiplayerSocketService.instance;
  final ValueNotifier<int> _queueSecondsNotifier = ValueNotifier<int>(0);
  StreamSubscription<Map<String, dynamic>>? _matchSub;
  StreamSubscription<Map<String, dynamic>>? _reconnectRequiredSub;
  Timer? _queueTimer;
  int _queueSeconds = 0;
  bool _queueDialogOpen = false;
  bool _matchmaking = false; // re-entrancy guard: one queue at a time

  // Profile
  bool _profileLoading = true;
  int _rating = 1200;
  int _ratingDelta = 0;
  int _winStreak = 0;
  List<Map<String, dynamic>> _matchHistory = [];
  RealtimeChannel? _ratingChannel;

  // Daily challenge
  Map<String, dynamic>? _daily;
  DateTime? _dailyExpiresAt;
  Duration _dailyRemaining = Duration.zero;
  Timer? _dailyTicker;

  @override
  void initState() {
    super.initState();
    _initProfile();
    _subscribeToRatingUpdates();
    _loadDaily();
  }

  @override
  void dispose() {
    _matchSub?.cancel();
    _reconnectRequiredSub?.cancel();
    _queueTimer?.cancel();
    _dailyTicker?.cancel();
    _queueSecondsNotifier.dispose();
    if (_ratingChannel != null) {
      Supabase.instance.client.removeChannel(_ratingChannel!);
    }
    super.dispose();
  }

  // ─── Profile Loading ───────────────────────────────────────────────────────

  /// Paints from cache instantly if we have one (no spinner), then always
  /// reconciles with the server in the background. Only shows the blocking
  /// spinner when there is truly no cached data yet (first-ever run).
  Future<void> _initProfile() async {
    final cached = await ProfileCacheStore.load(widget.userId);
    if (!mounted) return;

    if (cached != null) {
      setState(() {
        _rating = cached.rating;
        _ratingDelta = cached.ratingDelta;
        _winStreak = cached.winStreak;
        _matchHistory = cached.matchHistory;
        _profileLoading = false;
      });
      _loadProfile(silent: true);
    } else {
      _loadProfile();
    }
  }

  /// Reloads rating + recent history. [silent] skips the loading spinner so a
  /// background Realtime refresh doesn't flash the UI.
  Future<void> _loadProfile({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _profileLoading = true);

    final userId = widget.userId;
    Map<String, dynamic>? profile;
    List<Map<String, dynamic>> history = const [];
    try {
      final results = await Future.wait([
        GameApiService.getUserProfile(userId),
        GameApiService.getUserMatchHistory(userId),
      ]);
      profile = results[0] as Map<String, dynamic>?;
      history = results[1] as List<Map<String, dynamic>>;
    } catch (_) {
      // Network failure/timeout: fall through and clear the spinner below,
      // leaving whatever is already in state (cache or previous fetch).
    }

    if (!mounted) return;

    if (profile == null && history.isEmpty) {
      setState(() => _profileLoading = false);
      return;
    }

    int delta = 0;
    int streak = 0;
    if (history.isNotEmpty) {
      delta = _deltaForViewer(history.first, userId);
      for (final match in history) {
        if (match['winner_id']?.toString() == userId) {
          streak++;
        } else {
          break;
        }
      }
    }

    final rating = (profile?['rating'] as num?)?.toInt() ?? _rating;
    final trimmedHistory = history.take(5).toList();

    setState(() {
      _rating = rating;
      _ratingDelta = delta;
      _winStreak = streak;
      _matchHistory = trimmedHistory;
      _profileLoading = false;
    });

    await ProfileCacheStore.save(
      userId: userId,
      rating: rating,
      ratingDelta: delta,
      winStreak: streak,
      matchHistory: trimmedHistory,
    );
  }

  /// Applies the rating/delta GameScreen already computed (passed back via
  /// its pop result) so the home rating updates with zero network latency
  /// and no spinner, then reconciles silently in the background to pick up
  /// match history / win streak / authoritative server state.
  void _applyMatchResultAndReconcile(Object? result) {
    if (!mounted) return;
    if (result is Map) {
      final rating = (result['rating'] as num?)?.toInt();
      final ratingDelta = (result['ratingDelta'] as num?)?.toInt();
      if (rating != null) {
        setState(() {
          _rating = rating;
          _ratingDelta = ratingDelta ?? _ratingDelta;
        });
      }
    }
    _loadProfile(silent: true);
  }

  /// The `games` row stores a single `rating_delta` (the winner's gain). With a
  /// fixed K-factor the loser's loss mirrors it, so flip the sign when the
  /// viewer wasn't the winner.
  int _deltaForViewer(Map<String, dynamic> match, String userId) {
    final stored = (match['rating_delta'] as num?)?.toInt() ?? 0;
    if (stored == 0) return 0;
    final won = match['winner_id']?.toString() == userId;
    final magnitude = stored.abs();
    return won ? magnitude : -magnitude;
  }

  /// Live-update the user's own rating on this device the moment any device
  /// finishes a match for them — keeps the home ELO in sync everywhere.
  void _subscribeToRatingUpdates() {
    _ratingChannel = Supabase.instance.client
        .channel('public:users:home:${widget.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.userId,
          ),
          callback: (_) => _loadProfile(silent: true),
        )
        .subscribe();
  }

  // ─── Matchmaking ───────────────────────────────────────────────────────────

  String _formatQueueTime(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _startMatchmaking() async {
    // Re-entrancy guard: a double-tap (or a re-tap while still queueing) must
    // not open a second queue/dialog.
    if (_matchmaking) return;

    // Can't start a new match while one is already in progress. A live match
    // keeps the user inside GameScreen, but an app-kill mid-game leaves a
    // resumable snapshot — resume that instead of queueing again.
    final active = await ActiveGameStore.load(widget.userId);
    if (active != null) {
      if (!mounted) return;
      final result = await Navigator.of(context).push(
        fadeThroughRoute(
          GameScreen(
            restoreFrom: active,
            highlightMistakes: widget.highlightMistakes,
            timerEnabled: widget.timerEnabled,
            currentUserId: widget.userId,
            multiplayerEnabled: active.multiplayer,
          ),
        ),
      );
      if (mounted) _applyMatchResultAndReconcile(result);
      return;
    }

    _matchmaking = true;
    try {
      bool matched = false;
      final userId = widget.userId;
      await _socketService.connect(userId);

      await _matchSub?.cancel();
      await _reconnectRequiredSub?.cancel();

      _matchSub = _socketService.matchFoundStream.listen((payload) async {
        if (!_queueDialogOpen || !mounted) return;
        final session = GameSession.fromMatchFound(payload);
        matched = true;
        _queueDialogOpen = false;
        _queueTimer?.cancel();
        Analytics.capture('match_found', props: {'wait_seconds': _queueSeconds});
        Navigator.of(context, rootNavigator: true).pop();

        final result = await Navigator.of(context).push(
          fadeThroughRoute(
            GameScreen(
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
        } else if (mounted) {
          _applyMatchResultAndReconcile(result);
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
          fadeThroughRoute(
            GameScreen(
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
      Analytics.capture('queue_started');
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        builder: (dialogContext) => _FindingOpponentDialog(
          secondsNotifier: _queueSecondsNotifier,
          formatTime: _formatQueueTime,
          onCancel: () {
            _queueDialogOpen = false;
            _queueTimer?.cancel();
            Analytics.capture('queue_cancelled',
                props: {'wait_seconds': _queueSeconds});
            Navigator.of(dialogContext).pop();
          },
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
        SnackBar(
          content: Text('Could not connect to matchmaking server at ${ApiConfig.socketUrl}'),
        ),
      );
    } finally {
      // Queue phase over (matched, cancelled, or errored). A match in progress
      // now lives in GameScreen; re-tapping PLAY is gated by the snapshot check.
      _matchmaking = false;
    }
  }

  // ─── Daily Challenge ─────────────────────────────────────────────────────────

  Future<void> _loadDaily() async {
    final daily = await GameApiService.getDailyChallenge();
    if (!mounted || daily == null) return;

    DateTime? expiresAt;
    final rawExpiry = daily['expiresAt']?.toString();
    if (rawExpiry != null) {
      expiresAt = DateTime.tryParse(rawExpiry)?.toLocal();
    }

    setState(() {
      _daily = daily;
      _dailyExpiresAt = expiresAt;
    });
    _startDailyTicker();
  }

  void _startDailyTicker() {
    _dailyTicker?.cancel();
    _tickDaily();
    _dailyTicker =
        Timer.periodic(const Duration(seconds: 1), (_) => _tickDaily());
  }

  void _tickDaily() {
    final expiresAt = _dailyExpiresAt;
    if (expiresAt == null) return;

    // Recompute from the wall clock each tick (don't decrement) so it stays
    // correct after the app is backgrounded/resumed.
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      // Rolled past ET midnight — fetch the next day's puzzle.
      _dailyTicker?.cancel();
      _loadDaily();
      return;
    }
    if (mounted) setState(() => _dailyRemaining = remaining);
  }

  String _formatCountdown(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  void _playDaily() {
    final daily = _daily;
    if (daily == null) return;
    HapticFeedback.mediumImpact();
    Analytics.capture('daily_opened',
        props: {'day_number': (daily['dayNumber'] as num?)?.toInt()});
    Navigator.of(context).push(
      fadeThroughRoute(
        GameScreen(
          initialSession: GameSession.fromJson(daily),
          highlightMistakes: widget.highlightMistakes,
          timerEnabled: widget.timerEnabled,
          currentUserId: widget.userId,
          multiplayerEnabled: false,
        ),
      ),
    );
  }

  // ─── UI Builders ───────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          UserAvatar(userId: widget.userId, size: 40),
          SettingsGearButton(onPressed: widget.onSettingsPressed),
        ],
      ),
    );
  }

  Widget _buildEloDisplay() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'YOUR RATING',
            style: TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          _profileLoading
              ? const SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.primary,
                  ),
                )
              : Text(
                  _rating.toString(),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 120,
                    fontWeight: FontWeight.w800,
                    height: 0.9,
                    letterSpacing: -3,
                  ),
                ),
          if (!_profileLoading && _ratingDelta != 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _ratingDelta > 0 ? Icons.trending_up : Icons.trending_down,
                  color: _ratingDelta > 0
                      ? AppColors.tertiaryContainer
                      : AppColors.error,
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(
                  '${_ratingDelta > 0 ? '+' : ''}$_ratingDelta',
                  style: TextStyle(
                    color: _ratingDelta > 0
                        ? AppColors.tertiaryContainer
                        : AppColors.error,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        Analytics.capture('play_tapped');
        _startMatchmaking();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 24),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'FIND AN OPPONENT',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'PLAY',
              style: TextStyle(
                color: Colors.white,
                fontSize: 56,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
                height: 1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Get ranked, challenge yourself',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyChallengeSection() {
    final daily = _daily;
    final difficultyLabel =
        (daily?['difficulty']?.toString() ?? 'hard').toUpperCase();
    final dayNumber = (daily?['dayNumber'] as num?)?.toInt();
    final countdown =
        _dailyExpiresAt == null ? '--:--:--' : _formatCountdown(_dailyRemaining);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              'Daily Challenge',
              style: TextStyle(
                color: AppColors.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'Expires in $countdown',
              style: const TextStyle(
                color: AppColors.outline,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: daily == null ? null : _playDaily,
            child: Container(
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
                              child: Text(
                                difficultyLabel,
                                style: const TextStyle(
                                  color: AppColors.onTertiaryContainer,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              dayNumber != null
                                  ? 'Daily #$dayNumber'
                                  : 'Loading…',
                              style: const TextStyle(
                                color: AppColors.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Today's Puzzle",
                          style: TextStyle(
                            color: AppColors.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          daily == null
                              ? 'Fetching today\'s board…'
                              : 'Tap to solve today\'s board',
                          style: const TextStyle(
                            color: AppColors.outline,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
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
                          color:
                              AppColors.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    child: Icon(
                      Icons.grid_on,
                      color: AppColors.outline.withValues(alpha: 0.3),
                      size: 40,
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

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '--:--';
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildMatchItem(Map<String, dynamic> match, {required bool isFirst}) {
    final isWin = match['winner_id']?.toString() == widget.userId;
    final duration = (match['duration'] as num?)?.toInt();
    final delta = _deltaForViewer(match, widget.userId);

    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 0 : 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isWin
                    ? AppColors.primary.withValues(alpha: 0.08)
                    : AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isWin ? Icons.emoji_events : Icons.close_rounded,
                color: isWin ? AppColors.primary : AppColors.outline,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isWin ? 'Won' : 'Lost',
                    style: TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Ranked • ${_formatDuration(duration)}',
                    style: const TextStyle(
                      color: AppColors.outline,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  delta == 0 ? '—' : (delta > 0 ? '+$delta' : '$delta'),
                  style: TextStyle(
                    color: delta >= 0
                        ? AppColors.tertiaryContainer
                        : AppColors.error,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
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
      ),
    );
  }

  Widget _buildWinStreak() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.local_fire_department,
              color: AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _winStreak.toString(),
                  style: const TextStyle(
                    color: AppColors.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Win Streak',
                  style: TextStyle(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
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
    final screenHeight = MediaQuery.of(context).size.height;
    final eloDisplayHeight = screenHeight * 0.25;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            SizedBox(
              height: eloDisplayHeight,
              child: _buildEloDisplay(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeroSection(),
                    const SizedBox(height: 32),
                    _buildDailyChallengeSection(),
                    const SizedBox(height: 32),
                    if (!_profileLoading) _buildWinStreak(),
                    if (!_profileLoading) const SizedBox(height: 32),
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

/// iOS-style "Finding Opponent" sheet: frosted glass card with a pulsing
/// radar icon, a tabular-figure queue timer, and a pill-shaped cancel button.
class _FindingOpponentDialog extends StatefulWidget {
  final ValueNotifier<int> secondsNotifier;
  final String Function(int) formatTime;
  final VoidCallback onCancel;

  const _FindingOpponentDialog({
    required this.secondsNotifier,
    required this.formatTime,
    required this.onCancel,
  });

  @override
  State<_FindingOpponentDialog> createState() =>
      _FindingOpponentDialogState();
}

class _FindingOpponentDialogState extends State<_FindingOpponentDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 88,
                  height: 88,
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, _) {
                      final t = _pulseController.value;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 88 * (0.7 + 0.3 * t),
                            height: 88 * (0.7 + 0.3 * t),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary
                                  .withValues(alpha: 0.12 * (1 - t)),
                            ),
                          ),
                          Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary,
                            ),
                            child: const Icon(Icons.bolt_rounded,
                                color: Colors.white, size: 32),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Finding Opponent',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Matching you with a similarly ranked player',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 22),
                ValueListenableBuilder<int>(
                  valueListenable: widget.secondsNotifier,
                  builder: (_, value, __) => Text(
                    widget.formatTime(value),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.surfaceContainerHigh,
                      foregroundColor: AppColors.error,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: widget.onCancel,
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
