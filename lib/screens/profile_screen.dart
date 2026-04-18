import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/game_api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  String _title = 'Analytical Sanctuary';
  String _userId = 'local_player';
  String _username = 'Analytical_You';
  int _rating = 1200;
  int _gamesPlayed = 0;
  int _wins = 0;
  int _bestTimeSeconds = 0;
  List<Map<String, dynamic>> _matchHistory = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('local_user_id') ?? 'local_player';

    final profile = await GameApiService.getUserProfile(userId);
    final history = await GameApiService.getUserMatchHistory(userId);

    int bestTime = 0;
    if (history.isNotEmpty) {
      final durations = history
          .map((m) => m['duration'])
          .whereType<num>()
          .map((n) => n.toInt())
          .where((s) => s > 0)
          .toList();
      if (durations.isNotEmpty) {
        durations.sort();
        bestTime = durations.first;
      }
    }

    if (!mounted) return;

    setState(() {
      _userId = userId;
      _username = (profile?['username']?.toString().isNotEmpty ?? false)
          ? profile!['username'].toString()
          : 'Analytical_You';
      _rating = (profile?['rating'] as num?)?.toInt() ?? 1200;
      _gamesPlayed = (profile?['games_played'] as num?)?.toInt() ?? 0;
      _wins = (profile?['wins'] as num?)?.toInt() ?? 0;
      _bestTimeSeconds = bestTime;
      _matchHistory = history;
      _loading = false;
    });
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

    return Container(
      color: const Color(0xFFF1F3F7),
      child: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadProfile,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.arrow_back, color: Color(0xFF0E46A7)),
                        const SizedBox(width: 10),
                        Text(
                          _title,
                          style: const TextStyle(
                            color: Color(0xFF0D2F87),
                            fontSize: 31,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: _loadProfile,
                          icon: const Icon(Icons.settings,
                              color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Stack(
                        children: [
                          Container(
                            width: 126,
                            height: 126,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                  color: const Color(0xFFDBE2EE), width: 3),
                              image: const DecorationImage(
                                image: NetworkImage(
                                  'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400&q=80',
                                ),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0E53BE),
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.settings,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: Text(
                        _username,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF10151E),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Center(
                      child: Text(
                        'ELITE PUZZLE MASTER',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
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
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('ELO',
                                style: TextStyle(
                                    fontSize: 12, color: Color(0xFF6B7280))),
                            const SizedBox(width: 10),
                            Text(
                              '$_rating',
                              style: const TextStyle(
                                fontSize: 18,
                                color: Color(0xFF0E46A7),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFDE6DE),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '↗+12',
                                style: TextStyle(
                                  color: Color(0xFFB42318),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
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
                      subtitle: 'Expert',
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
  final String? subtitle;
  final bool highlighted;

  const _ProfileCard({
    required this.title,
    required this.value,
    this.subtitle,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = highlighted ? const Color(0xFF0E53BE) : Colors.white;
    final fg = highlighted ? Colors.white : const Color(0xFF10151E);
    final sub = highlighted ? Colors.white70 : const Color(0xFF6B7280);

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 42,
                  color: fg,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 6),
                  child: Text(
                    subtitle!,
                    style: TextStyle(color: sub, fontSize: 14),
                  ),
                ),
            ],
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
        color: const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF0E53BE)),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF10151E),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: won ? const Color(0xFFFDE6DE) : const Color(0xFFDDE5FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.grid_4x4,
                color: won ? const Color(0xFF9B1C1C) : const Color(0xFF0E46A7)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
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
                  color: Color(0xFF0D3897),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                status,
                style: TextStyle(
                  fontSize: 12,
                  color:
                      won ? const Color(0xFFB42318) : const Color(0xFF6B7280),
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
