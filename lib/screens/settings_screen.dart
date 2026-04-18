import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  final bool darkMode;
  final bool highlightMistakes;
  final bool timerEnabled;
  final bool soundEffects;
  final ValueChanged<bool> onDarkModeChanged;
  final ValueChanged<bool> onHighlightMistakesChanged;
  final ValueChanged<bool> onTimerChanged;
  final ValueChanged<bool> onSoundEffectsChanged;

  const SettingsScreen({
    Key? key,
    required this.darkMode,
    required this.highlightMistakes,
    required this.timerEnabled,
    required this.soundEffects,
    required this.onDarkModeChanged,
    required this.onHighlightMistakesChanged,
    required this.onTimerChanged,
    required this.onSoundEffectsChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SwitchListTile(
          title: const Text('Dark mode'),
          value: darkMode,
          onChanged: onDarkModeChanged,
        ),
        SwitchListTile(
          title: const Text('Highlight mistakes'),
          value: highlightMistakes,
          onChanged: onHighlightMistakesChanged,
        ),
        SwitchListTile(
          title: const Text('Timer'),
          value: timerEnabled,
          onChanged: onTimerChanged,
        ),
        SwitchListTile(
          title: const Text('Sound effects'),
          value: soundEffects,
          onChanged: onSoundEffectsChanged,
        ),
      ],
    );
  }
}
