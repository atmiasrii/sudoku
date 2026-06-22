import 'package:flutter/material.dart';

/// A polished, deterministic avatar for a user.
///
/// Renders a smooth two-tone gradient (Vercel/Linear style) seeded from
/// [userId], with a monogram on top — the first letter of [name] when given,
/// otherwise the first alphanumeric of the id. The same id always produces the
/// same gradient on every device: the seed comes from an explicit FNV-1a hash
/// rather than `String.hashCode`, which is not stable across platforms.
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
    final seed = _fnv1a(userId);
    final gradient = _gradients[seed % _gradients.length];
    final letter = _monogram(name, userId);
    // Rotate the gradient a little per-seed so two adjacent palettes still read
    // as distinct avatars.
    final angle = ((seed >> 8) % 4) * 0.7;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment(-1, -1 + angle),
          end: Alignment(1, 1 - angle),
        ),
        boxShadow: [
          BoxShadow(
            color: gradient.last.withValues(alpha: 0.35),
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

/// FNV-1a 32-bit hash. Deterministic and identical on every platform, so a
/// user's avatar is the same everywhere.
int _fnv1a(String input) {
  const int prime = 0x01000193;
  int hash = 0x811c9dc5;
  for (final codeUnit in input.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * prime) & 0xFFFFFFFF;
  }
  return hash;
}

/// Curated gradient pairs — vibrant but tasteful, each with enough contrast for
/// white text.
const List<List<Color>> _gradients = [
  [Color(0xFF6366F1), Color(0xFF8B5CF6)], // indigo → violet
  [Color(0xFF3B82F6), Color(0xFF06B6D4)], // blue → cyan
  [Color(0xFF14B8A6), Color(0xFF10B981)], // teal → emerald
  [Color(0xFF10B981), Color(0xFF84CC16)], // emerald → lime
  [Color(0xFFF59E0B), Color(0xFFF97316)], // amber → orange
  [Color(0xFFF97316), Color(0xFFEF4444)], // orange → red
  [Color(0xFFEF4444), Color(0xFFEC4899)], // red → pink
  [Color(0xFFEC4899), Color(0xFFA855F7)], // pink → purple
  [Color(0xFF8B5CF6), Color(0xFF6366F1)], // violet → indigo
  [Color(0xFF0EA5E9), Color(0xFF6366F1)], // sky → indigo
  [Color(0xFFF43F5E), Color(0xFFF59E0B)], // rose → amber
  [Color(0xFF06B6D4), Color(0xFF3B82F6)], // cyan → blue
];
