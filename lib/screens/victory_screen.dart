import 'package:flutter/material.dart';

class VictoryScreen extends StatelessWidget {
  final bool won;
  final bool multiplayer;
  final bool allowClose;
  final String playerName;
  final int playerRating;
  final int ratingDelta;
  final String timeText;
  final double accuracy;
  final int mistakes;
  final int progress;
  final String difficulty;

  const VictoryScreen({
    super.key,
    required this.won,
    required this.multiplayer,
    this.allowClose = false,
    required this.playerName,
    required this.playerRating,
    required this.ratingDelta,
    required this.timeText,
    required this.accuracy,
    required this.mistakes,
    required this.progress,
    required this.difficulty,
  });

  String _nextRankLabel(int rating) {
    if (rating >= 2500) return 'Grandmaster';
    if (rating >= 2200) return 'Master';
    if (rating >= 1800) return 'Expert';
    return 'Challenger';
  }

  @override
  Widget build(BuildContext context) {
    final pointsInTier = playerRating % 100;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          color: const Color(0xFFF1F3F7),
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0xFF0A0D14),
                      ),
                      child: const Icon(Icons.person, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$playerRating',
                      style: const TextStyle(
                        color: Color(0xFF0E46A7),
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.0,
                      ),
                    ),
                    const Spacer(),
                    if (allowClose)
                      IconButton(
                        onPressed: () => Navigator.of(context).pop('close'),
                        icon: const Icon(Icons.close, size: 22),
                      )
                    else
                      IconButton(
                        onPressed: () => Navigator.of(context).pop('find_new'),
                        icon: const Icon(Icons.settings, size: 22),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E46A7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      multiplayer ? 'RANKED MATCH' : 'PRACTICE MATCH',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    won ? 'VICTORY' : 'DEFEAT',
                    style: const TextStyle(
                      color: Color(0xFF0E46A7),
                      fontSize: 56,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -2.2,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    won
                        ? 'Masterfully solved in record time.'
                        : 'Tough match. Review and come back stronger.',
                    style: const TextStyle(
                      color: Color(0xFF1F2937),
                      fontSize: 17,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'COMPETITIVE STANDING',
                        style: TextStyle(
                          fontSize: 20,
                          letterSpacing: 1.0,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$playerRating',
                            style: const TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF10151E),
                              letterSpacing: -2.5,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${ratingDelta >= 0 ? '+' : ''}$ratingDelta',
                            style: const TextStyle(
                              color: Color(0xFFB42318),
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            'Next Rank: ${_nextRankLabel(playerRating)}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF1F2937),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '$pointsInTier/100 Points',
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          minHeight: 8,
                          value: pointsInTier / 100,
                          backgroundColor: const Color(0xFFD1D5DB),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF0E46A7)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(label: 'MATCH TIME', value: timeText),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: 'ACCURACY',
                        value: '${accuracy.toStringAsFixed(1)}%',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(label: 'MISTAKES', value: '$mistakes'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(label: 'DIFFICULTY', value: difficulty),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0E53BE),
                            foregroundColor: Colors.white,
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop('rematch'),
                          child: Text(
                            multiplayer ? 'Rematch' : 'Play Again',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: Color(0xFFB8BFCE),
                              width: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            foregroundColor: const Color(0xFF10151E),
                          ),
                          onPressed: () =>
                              Navigator.of(context).pop('find_new'),
                          child: Text(
                            multiplayer ? 'New Match' : 'Back Home',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 128,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFECEFF4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 13,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF10151E),
              fontSize: 34,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
