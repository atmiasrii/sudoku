import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_colors.dart';
import '../services/auth_service.dart';
import '../services/game_api_service.dart';
import '../widgets/screen_header.dart';
import '../widgets/user_avatar.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  final VoidCallback? onSettingsPressed;

  const ProfileScreen({
    super.key,
    required this.userId,
    this.onSettingsPressed,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  String _userId = 'local_player';
  String _username = 'Player';
  int _rating = 1200;
  int _ratingDelta = 0;
  int _gamesPlayed = 0;
  int _wins = 0;
  int _bestTimeSeconds = 0;
  List<Map<String, dynamic>> _matchHistory = <Map<String, dynamic>>[];
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    if (_channel != null) {
      Supabase.instance.client.removeChannel(_channel!);
    }
    super.dispose();
  }

  /// [silent] skips the full-screen spinner so a background Realtime refresh
  /// (a match finishing) updates stats in place instead of flashing the page.
  Future<void> _loadProfile({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
      });
    }

    final userId = widget.userId;
    final profile = await GameApiService.getUserProfile(userId);
    final history = await GameApiService.getUserMatchHistory(userId);

    // Derive stats from the match history (source of truth). The users-table
    // counters can lag or stay zero (only bumped for some match types), so the
    // history is what the profile reports.
    final gamesPlayed = history.length;
    final wins = history
        .where((m) => m['winner_id']?.toString() == userId)
        .length;

    // Best time = fastest completed solve, i.e. the shortest duration among
    // matches the user won. Falls back to the fastest of any match if no wins.
    int bestTime = _minDuration(
        history.where((m) => m['winner_id']?.toString() == userId));
    if (bestTime == 0) bestTime = _minDuration(history);

    final delta =
        history.isNotEmpty ? _deltaForViewer(history.first, userId) : 0;

    if (!mounted) return;

    setState(() {
      _userId = userId;
      _username = (profile?['username']?.toString().isNotEmpty ?? false)
          ? profile!['username'].toString()
          : AuthService.instance.displayName();
      _rating = (profile?['rating'] as num?)?.toInt() ?? 1200;
      _ratingDelta = delta;
      _gamesPlayed = gamesPlayed;
      _wins = wins;
      _bestTimeSeconds = bestTime;
      _matchHistory = history;
      _loading = false;
    });
  }

  /// Smallest positive `duration` across the given matches, or 0 if none.
  int _minDuration(Iterable<Map<String, dynamic>> matches) {
    final durations = matches
        .map((m) => (m['duration'] as num?)?.toInt() ?? 0)
        .where((s) => s > 0)
        .toList();
    if (durations.isEmpty) return 0;
    durations.sort();
    return durations.first;
  }

  void _subscribeToRealtime() {
    _channel = Supabase.instance.client
        .channel('public:users:profile:${widget.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.userId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (!mounted) return;
            // Only rating comes from the users row; matches/wins/best-time are
            // derived from history (refreshed by the games-insert handler).
            setState(() {
              _rating = (row['rating'] as num?)?.toInt() ?? _rating;
            });
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'games',
          callback: (payload) {
            final row = payload.newRecord;
            if (row['player1_id'] == widget.userId || row['player2_id'] == widget.userId) {
              _loadProfile(silent: true);
            }
          },
        )
        .subscribe();
  }

  /// The `games` row stores one `rating_delta` (the winner's gain). With a
  /// fixed K-factor the loser's loss mirrors it, so flip the sign when the
  /// viewer wasn't the winner.
  int _deltaForViewer(Map<String, dynamic> match, String userId) {
    final stored = (match['rating_delta'] as num?)?.toInt() ?? 0;
    if (stored == 0) return 0;
    final won = match['winner_id']?.toString() == userId;
    return won ? stored.abs() : -stored.abs();
  }

  String _tierForRating(int rating) {
    if (rating < 1200) return 'Novice';
    if (rating < 1500) return 'Skilled';
    if (rating < 1800) return 'Expert';
    return 'Master';
  }

  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final winRate =
        _gamesPlayed > 0 ? ((_wins / _gamesPlayed) * 100).round() : 0;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : RefreshIndicator(
                onRefresh: _loadProfile,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        UserAvatar(userId: widget.userId, name: _username, size: 40),
                        SettingsGearButton(onPressed: widget.onSettingsPressed),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        _username,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        _tierForRating(_rating).toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.onSurfaceVariant,
                          letterSpacing: 1,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('RATING',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.onSurfaceVariant)),
                            const SizedBox(width: 10),
                            Text(
                              '$_rating',
                              style: const TextStyle(
                                fontSize: 18,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (_ratingDelta != 0) ...[
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _ratingDelta > 0
                                      ? AppColors.tertiaryContainer.withValues(alpha: 0.2)
                                      : AppColors.error.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${_ratingDelta > 0 ? '+' : ''}$_ratingDelta',
                                  style: TextStyle(
                                    color: _ratingDelta > 0
                                        ? AppColors.tertiaryContainer
                                        : AppColors.error,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _ProfileCard(
                      title: 'TOTAL MATCHES',
                      value: _gamesPlayed.toString(),
                    ),
                    const SizedBox(height: 12),
                    _ProfileCard(
                      title: 'WIN RATE',
                      value: '$winRate%',
                      highlighted: true,
                    ),
                    const SizedBox(height: 12),
                    _ProfileCard(
                      title: 'BEST TIME',
                      value: _bestTimeSeconds > 0
                          ? _formatDuration(_bestTimeSeconds)
                          : '--:--',
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Achievements',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Achievement detail view coming soon.')),
                            );
                          },
                          child: const Text('View All'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 136,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: const [
                          _AchievementTile(
                              icon: Icons.military_tech_outlined,
                              title: 'Master Tactician'),
                          SizedBox(width: 12),
                          _AchievementTile(
                              icon: Icons.flash_on, title: 'Fastest Fingers'),
                          SizedBox(width: 12),
                          _AchievementTile(
                              icon: Icons.verified, title: 'Perfect Grid'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Recent Match History',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    if (_matchHistory.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text('No match history available yet.'),
                      )
                    else
                      ..._matchHistory.take(5).map((match) {
                        final duration =
                            (match['duration'] as num?)?.toInt() ?? 0;
                        final createdAt = match['created_at']?.toString() ?? '';
                        final winnerId = match['winner_id']?.toString() ?? '';
                        final won = winnerId == _userId;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _HistoryCard(
                            title: '${won ? 'Won' : 'Lost'} Ranked Match',
                            subtitle:
                                createdAt.isNotEmpty ? createdAt : 'Recent',
                            duration: duration > 0
                                ? _formatDuration(duration)
                                : '--:--',
                            status: won ? 'VICTORY' : 'COMPLETED',
                            won: won,
                          ),
                        );
                      }),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String title;
  final String value;
  final bool highlighted;

  const _ProfileCard({
    required this.title,
    required this.value,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = highlighted ? AppColors.primary : AppColors.surfaceContainerLowest;
    final fg = highlighted ? Colors.white : AppColors.onSurface;
    final sub = highlighted ? Colors.white70 : AppColors.onSurfaceVariant;

    return Container(
      height: 120,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              letterSpacing: 1,
              color: sub,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 42,
              color: fg,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  final IconData icon;
  final String title;

  const _AchievementTile({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String duration;
  final String status;
  final bool won;

  const _HistoryCard({
    required this.title,
    required this.subtitle,
    required this.duration,
    required this.status,
    required this.won,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: won
                  ? AppColors.tertiaryContainer.withValues(alpha: 0.15)
                  : AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.grid_4x4,
                color: won ? AppColors.tertiaryContainer : AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600,
                      color: AppColors.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                duration,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                status,
                style: TextStyle(
                  fontSize: 12,
                  color: won ? AppColors.tertiaryContainer : AppColors.outline,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
