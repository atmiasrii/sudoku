import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../widgets/user_avatar.dart';

class VictoryScreen extends StatelessWidget {
  final bool won;
  final bool multiplayer;
  final bool allowClose;
  final String playerName;
  final String? playerUserId;
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
    this.playerUserId,
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
          color: AppColors.surface,
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    UserAvatar(
                      userId: playerUserId ?? 'player',
                      name: playerName,
                      size: 42,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$playerRating',
                      style: const TextStyle(
                        color: AppColors.primary,
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
                      color: AppColors.primary,
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
                      color: AppColors.primary,
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
                      color: AppColors.onSurface,
                      fontSize: 17,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
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
                          color: AppColors.onSurface,
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
                              color: AppColors.onSurface,
                              letterSpacing: -2.5,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${ratingDelta >= 0 ? '+' : ''}$ratingDelta',
                            style: TextStyle(
                              color: ratingDelta >= 0 ? AppColors.tertiaryContainer : AppColors.error,
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
                              color: AppColors.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '$pointsInTier/100 Points',
                            style: const TextStyle(
                              color: AppColors.onSurfaceVariant,
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
                          backgroundColor: AppColors.surfaceContainerHigh,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.primary),
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
                      child: _StatCard(
                        label: 'DIFFICULTY',
                        value: difficulty.isEmpty
                            ? difficulty
                            : '${difficulty[0].toUpperCase()}${difficulty.substring(1).toLowerCase()}',
                      ),
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
                            backgroundColor: AppColors.primary,
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
                              color: AppColors.outlineVariant,
                              width: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            foregroundColor: AppColors.onSurface,
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
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 13,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: AppColors.onSurface,
                fontSize: 34,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
