import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_colors.dart';
import '../config/analytics_config.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';

class AppSettingsSheet extends StatefulWidget {
  final bool darkMode;
  final bool highlightMistakes;
  final bool timerEnabled;
  final bool soundEffects;
  final ValueChanged<bool> onDarkModeChanged;
  final ValueChanged<bool> onHighlightMistakesChanged;
  final ValueChanged<bool> onTimerChanged;
  final ValueChanged<bool> onSoundEffectsChanged;
  final VoidCallback? onClosePressed;

  const AppSettingsSheet({
    super.key,
    required this.darkMode,
    required this.highlightMistakes,
    required this.timerEnabled,
    required this.soundEffects,
    required this.onDarkModeChanged,
    required this.onHighlightMistakesChanged,
    required this.onTimerChanged,
    required this.onSoundEffectsChanged,
    this.onClosePressed,
  });

  @override
  State<AppSettingsSheet> createState() => _AppSettingsSheetState();
}

class _AppSettingsSheetState extends State<AppSettingsSheet> {
  bool _dailyChallengesNotif = true;
  bool _rankUpdatesNotif = false;
  bool _analyticsOptOut = Analytics.optedOut;

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
          'You will be returned to the login screen. Continue?',
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
    await AuthService.instance.signOut();
  }

  Future<void> _handleManageAccount() async {
    final currentEmail = AuthService.instance.currentUser?.email ?? '';
    final controller = TextEditingController(text: currentEmail);

    if (!mounted) return;
    final newEmail = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Manage Account',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.onSurface),
        ),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'New email',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (newEmail == null || newEmail.isEmpty || !mounted) return;

    try {
      await AuthService.instance.updateEmail(newEmail);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email updated successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _handleChangePassword() async {
    String newPassword = '';
    String confirmPassword = '';

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Change Password',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.onSurface),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'New password',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) => newPassword = v,
            ),
            const SizedBox(height: 12),
            TextField(
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'Confirm password',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) => confirmPassword = v,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (newPassword.isEmpty || confirmPassword.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill all fields')),
                );
                return;
              }
              if (newPassword != confirmPassword) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Passwords do not match')),
                );
                return;
              }
              if (newPassword.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password must be at least 6 characters')),
                );
                return;
              }
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await AuthService.instance.updatePassword(newPassword);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Settings',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.primary),
                onPressed: widget.onClosePressed ?? () => Navigator.of(context).pop(),
                splashRadius: 20,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Game Preferences
          _sectionHeader('Game Preferences'),
          _toggleItem(
            title: 'Show Timer',
            subtitle: 'Track your resolution speed',
            value: widget.timerEnabled,
            onChanged: (v) {
              Analytics.capture('setting_changed',
                  props: {'key': 'timer', 'value': v});
              widget.onTimerChanged(v);
            },
            isFirst: true,
          ),
          _toggleItem(
            title: 'Highlight Duplicates',
            subtitle: 'Instantly spot illegal moves',
            value: widget.highlightMistakes,
            onChanged: (v) {
              Analytics.capture('setting_changed',
                  props: {'key': 'highlight_mistakes', 'value': v});
              widget.onHighlightMistakesChanged(v);
            },
          ),
          _toggleItem(
            title: 'Smart Hints',
            subtitle: 'Show logical explanations for hints',
            value: widget.soundEffects,
            onChanged: (v) {
              Analytics.capture('setting_changed',
                  props: {'key': 'smart_hints', 'value': v});
              widget.onSoundEffectsChanged(v);
            },
            isLast: true,
          ),

          const SizedBox(height: 32),

          // Account
          _sectionHeader('Account'),
          _chevronItem(
            title: 'Email',
            subtitle: 'Manage your account',
            onTap: _handleManageAccount,
            isFirst: true,
          ),
          _chevronItem(
            title: 'Change Password',
            subtitle: 'Keep your account secure',
            onTap: _handleChangePassword,
            isLast: true,
          ),

          const SizedBox(height: 32),

          // Notifications
          _sectionHeader('Notifications'),
          _toggleItem(
            title: 'Daily Challenges',
            subtitle: 'Receive alerts for new elite puzzles',
            value: _dailyChallengesNotif,
            onChanged: (v) {
              setState(() => _dailyChallengesNotif = v);
              _setNotifPref('notif_daily', v);
              Analytics.capture('setting_changed',
                  props: {'key': 'notif_daily', 'value': v});
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
              Analytics.capture('setting_changed',
                  props: {'key': 'notif_rank', 'value': v});
            },
            isLast: true,
          ),

          if (AnalyticsConfig.enabled) ...[
            const SizedBox(height: 32),
            _sectionHeader('Privacy'),
            _toggleItem(
              title: 'Usage Analytics',
              subtitle: 'Share anonymous usage data to improve the app',
              value: !_analyticsOptOut,
              onChanged: (v) {
                setState(() => _analyticsOptOut = !v);
                Analytics.setOptOut(!v);
              },
              isFirst: true,
              isLast: true,
            ),
          ],

          const SizedBox(height: 40),

          // Sign Out
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
    );
  }
}

Future<void> showAppSettingsSheet(
  BuildContext context, {
  required bool darkMode,
  required bool highlightMistakes,
  required bool timerEnabled,
  required bool soundEffects,
  required ValueChanged<bool> onDarkModeChanged,
  required ValueChanged<bool> onHighlightMistakesChanged,
  required ValueChanged<bool> onTimerChanged,
  required ValueChanged<bool> onSoundEffectsChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => FractionallySizedBox(
      heightFactor: 0.9,
      child: AppSettingsSheet(
        darkMode: darkMode,
        highlightMistakes: highlightMistakes,
        timerEnabled: timerEnabled,
        soundEffects: soundEffects,
        onDarkModeChanged: onDarkModeChanged,
        onHighlightMistakesChanged: onHighlightMistakesChanged,
        onTimerChanged: onTimerChanged,
        onSoundEffectsChanged: onSoundEffectsChanged,
        onClosePressed: () => Navigator.of(ctx).pop(),
      ),
    ),
  );
}
