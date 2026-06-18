import 'package:flutter/material.dart';

import '../app_colors.dart';

class SettingsGearButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const SettingsGearButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings_outlined, color: AppColors.onSurfaceVariant),
      onPressed: onPressed,
      splashRadius: 20,
    );
  }
}
