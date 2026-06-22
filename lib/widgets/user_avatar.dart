import 'package:flutter/material.dart';

/// A polished avatar for a user.
///
/// Uniform near-black disc (matches the app's monochrome theme) with a white
/// monogram on top — the first letter of [name] when given, otherwise the first
/// alphanumeric of the id. A glossy highlight, inner ring, and soft shadow give
/// it depth without color.
class UserAvatar extends StatelessWidget {
  final String userId;
  final String? name;
  final double size;

  const UserAvatar({
    super.key,
    required this.userId,
    this.name,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final letter = _monogram(name, userId);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Uniform near-black for everyone to match the app's monochrome theme.
        gradient: const LinearGradient(
          colors: [Color(0xFF2A2A2A), Color(0xFF111111)],
          begin: Alignment(-1, -1),
          end: Alignment(1, 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: size * 0.18,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glossy top-left highlight for depth.
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.5, -0.6),
                radius: 1.0,
                colors: [
                  Colors.white.withValues(alpha: 0.28),
                  Colors.white.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.7],
              ),
            ),
          ),
          // Thin inner ring to crisp the edge on light and dark surfaces.
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: size * 0.03,
              ),
            ),
          ),
          if (letter != null)
            Text(
              letter,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.44,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                height: 1.0,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: size * 0.04,
                    offset: Offset(0, size * 0.02),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// First letter of [name]; falls back to the first alphanumeric character of
/// [userId]. Always uppercase. Null only if nothing usable exists.
String? _monogram(String? name, String userId) {
  if (name != null) {
    for (final ch in name.trim().split('')) {
      if (RegExp(r'[A-Za-z0-9]').hasMatch(ch)) return ch.toUpperCase();
    }
  }
  for (final ch in userId.split('')) {
    if (RegExp(r'[A-Za-z0-9]').hasMatch(ch)) return ch.toUpperCase();
  }
  return null;
}
