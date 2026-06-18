import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_colors.dart';
import '../services/game_api_service.dart';
import '../widgets/screen_header.dart';
import '../widgets/user_avatar.dart';

class RankingsScreen extends StatefulWidget {
  final String userId;
  final VoidCallback? onSettingsPressed;

  const RankingsScreen({
    super.key,
    required this.userId,
    this.onSettingsPressed,
  });

  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends State<RankingsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _players = const [];
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeToRatingUpdates();
  }

  @override
  void dispose() {
    if (_channel != null) {
      Supabase.instance.client.removeChannel(_channel!);
    }
    super.dispose();
  }

  /// [silent] skips the full-screen spinner so a background Realtime refresh
  /// (any player's rating changing) just re-sorts the list in place.
  Future<void> _load({bool silent = false}) async {
    if (mounted && !silent) setState(() => _loading = true);
    final players = await GameApiService.getLeaderboard(limit: 50);
    if (!mounted) return;
    setState(() {
      _players = players;
      _loading = false;
    });
  }

  /// Any rating change on any device re-ranks the board live. The `users`
  /// table is the single source of truth — this keeps the leaderboard in sync
  /// with it without a manual pull-to-refresh.
  void _subscribeToRatingUpdates() {
    _channel = Supabase.instance.client
        .channel('public:users:leaderboard')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          callback: (_) => _load(silent: true),
        )
        .subscribe();
  }

  int get _myRank {
    for (var i = 0; i < _players.length; i++) {
      if (_players[i]['id']?.toString() == widget.userId) return i + 1;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.primary,
                      child: _players.isEmpty
                          ? _buildEmpty()
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 8, 20, 28),
                              itemCount: _players.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) => _buildRow(i),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final rank = _myRank;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
      child: Row(
        children: [
          const Text(
            'Rankings',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          if (!_loading && rank > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primaryFixed,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                'You · #$rank',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          SettingsGearButton(onPressed: widget.onSettingsPressed),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      children: const [
        SizedBox(height: 120),
        Icon(Icons.leaderboard, size: 64, color: AppColors.outlineVariant),
        SizedBox(height: 16),
        Center(
          child: Text(
            'No players ranked yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(int index) {
    final player = _players[index];
    final rank = index + 1;
    final isMe = player['id']?.toString() == widget.userId;
    final name = player['username']?.toString() ?? 'Player';
    final rating = (player['rating'] as num?)?.toInt() ?? 1200;
    final wins = (player['wins'] as num?)?.toInt() ?? 0;

    final medal = _medalColor(rank);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isMe
            ? AppColors.primary.withValues(alpha: 0.08)
            : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: isMe
            ? Border.all(color: AppColors.primary, width: 1.5)
            : Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: medal != null
                ? Icon(Icons.emoji_events, color: medal, size: 24)
                : Text(
                    '$rank',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.outline,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          UserAvatar(
            userId: player['id']?.toString() ?? 'unknown',
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '$name (You)' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.onSurface,
                    fontSize: 15,
                    fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$wins wins',
                  style: const TextStyle(
                    color: AppColors.outline,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$rating',
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Color? _medalColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFD4AF37); // gold
      case 2:
        return const Color(0xFF9DA9B3); // silver
      case 3:
        return const Color(0xFFB87333); // bronze
      default:
        return null;
    }
  }
}
