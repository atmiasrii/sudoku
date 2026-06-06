import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_colors.dart';

class SettingsScreen extends StatefulWidget {
  final bool darkMode;
  final bool highlightMistakes;
  final bool timerEnabled;
  final bool soundEffects;
  final ValueChanged<bool> onDarkModeChanged;
  final ValueChanged<bool> onHighlightMistakesChanged;
  final ValueChanged<bool> onTimerChanged;
  final ValueChanged<bool> onSoundEffectsChanged;
  final VoidCallback? onNavigateToHome;

  const SettingsScreen({
    super.key,
    required this.darkMode,
    required this.highlightMistakes,
    required this.timerEnabled,
    required this.soundEffects,
    required this.onDarkModeChanged,
    required this.onHighlightMistakesChanged,
    required this.onTimerChanged,
    required this.onSoundEffectsChanged,
    this.onNavigateToHome,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _dailyChallengesNotif = true;
  bool _rankUpdatesNotif = false;

  @override
  void initState() {
    super.initState();
    _loadNotifPrefs();
  }

  Future<void> _loadNotifPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _dailyChallengesNotif = prefs.getBool('notif_daily') ?? true;
      _rankUpdatesNotif = prefs.getBool('notif_rank') ?? false;
    });
  }

  Future<void> _setNotifPref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _handleSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Sign Out',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.onSurface),
        ),
        content: const Text(
          'Your local session will be cleared. Continue?',
          style: TextStyle(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('local_user_id');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Signed out. A new session will start on next match.')),
    );
    widget.onNavigateToHome?.call();
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: AppColors.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.6,
        ),
      ),
    );
  }

  Widget _toggleItem({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.vertical(
          top: isFirst ? const Radius.circular(12) : Radius.zero,
          bottom: isLast ? const Radius.circular(12) : Radius.zero,
        ),
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0x18424654), width: 0.5),
              ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
            inactiveThumbColor: AppColors.outline,
            inactiveTrackColor: AppColors.surfaceVariant,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _chevronItem({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.vertical(
            top: isFirst ? const Radius.circular(12) : Radius.zero,
            bottom: isLast ? const Radius.circular(12) : Radius.zero,
          ),
          border: isLast
              ? null
              : const Border(
                  bottom: BorderSide(color: Color(0x18424654), width: 0.5),
                ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.outline, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(8, 12, 24, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: AppColors.primary),
                    onPressed: widget.onNavigateToHome ?? () {},
                    splashRadius: 20,
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Analytical Sanctuary',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const Text(
                    'SUDOKU ROYALE',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.5,
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Game Preferences ──
                    _sectionHeader('Game Preferences'),
                    _toggleItem(
                      title: 'Show Timer',
                      subtitle: 'Track your resolution speed',
                      value: widget.timerEnabled,
                      onChanged: widget.onTimerChanged,
                      isFirst: true,
                    ),
                    _toggleItem(
                      title: 'Highlight Duplicates',
                      subtitle: 'Instantly spot illegal moves',
                      value: widget.highlightMistakes,
                      onChanged: widget.onHighlightMistakesChanged,
                    ),
                    _toggleItem(
                      title: 'Smart Hints',
                      subtitle: 'Show logical explanations for hints',
                      value: widget.soundEffects,
                      onChanged: widget.onSoundEffectsChanged,
                      isLast: true,
                    ),

                    const SizedBox(height: 32),

                    // ── Account ──
                    _sectionHeader('Account'),
                    _chevronItem(
                      title: 'Email',
                      subtitle: 'Manage your account',
                      onTap: () {},
                      isFirst: true,
                    ),
                    _chevronItem(
                      title: 'Change Password',
                      subtitle: 'Keep your account secure',
                      onTap: () {},
                      isLast: true,
                    ),

                    const SizedBox(height: 32),

                    // ── Notifications ──
                    _sectionHeader('Notifications'),
                    _toggleItem(
                      title: 'Daily Challenges',
                      subtitle: 'Receive alerts for new elite puzzles',
                      value: _dailyChallengesNotif,
                      onChanged: (v) {
                        setState(() => _dailyChallengesNotif = v);
                        _setNotifPref('notif_daily', v);
                      },
                      isFirst: true,
                    ),
                    _toggleItem(
                      title: 'Rank Updates',
                      subtitle: 'Get notified when your global rank changes',
                      value: _rankUpdatesNotif,
                      onChanged: (v) {
                        setState(() => _rankUpdatesNotif = v);
                        _setNotifPref('notif_rank', v);
                      },
                      isLast: true,
                    ),

                    const SizedBox(height: 40),

                    // ── Sign Out ──
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: Color(0x1ABA1A1A)),
                          backgroundColor: const Color(0x0CBA1A1A),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _handleSignOut,
                        child: const Text(
                          'Sign Out',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
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
