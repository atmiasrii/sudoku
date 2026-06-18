import 'package:flutter/material.dart';

import '../app_colors.dart';

/// A deterministic, monochrome geometric identicon for a user.
///
/// Renders a symmetric 5×5 block pattern (GitHub-style) seeded from [userId],
/// in grayscale only so it matches the app's B&W theme. The same id always
/// produces the same avatar on every device — the seed comes from an explicit
/// FNV-1a hash rather than `String.hashCode`, which is not stable across
/// platforms/SDK versions.
class UserAvatar extends StatelessWidget {
  final String userId;
  final double size;

  const UserAvatar({
    super.key,
    required this.userId,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final seed = _fnv1a(userId);

    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: AppColors.surfaceContainerHigh,
        child: CustomPaint(
          painter: _IdenticonPainter(seed: seed),
          size: Size(size, size),
        ),
      ),
    );
  }
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

class _IdenticonPainter extends CustomPainter {
  final int seed;

  /// Grayscale tones for the filled blocks — all within the app's mono range.
  static const List<Color> _tones = [
    Color(0xFF1A1A1A),
    Color(0xFF2A2A2A),
    Color(0xFF3C3C3C),
    Color(0xFF505050),
  ];

  _IdenticonPainter({required this.seed});

  Color get _tone => _tones[(seed >> 28) & 0x3];

  @override
  void paint(Canvas canvas, Size size) {
    // 5×5 grid inset within the circle so corner blocks aren't clipped to
    // slivers by the ClipOval.
    const cells = 5;
    final gridSize = size.width * 0.74;
    final origin = (size.width - gridSize) / 2;
    final cellSize = gridSize / cells;
    final blockRadius = Radius.circular(cellSize * 0.2);

    final paint = Paint()
      ..color = _tone
      ..style = PaintingStyle.fill;

    // Build the symmetric fill grid: the left 3 columns (15 cells) come from
    // the hash bits, columns 3 and 4 mirror columns 1 and 0.
    final filled = List.generate(cells, (_) => List<bool>.filled(cells, false));
    var bit = 0;
    var anyFilled = false;
    var anyEmpty = false;
    for (var col = 0; col <= 2; col++) {
      for (var row = 0; row < cells; row++) {
        final on = ((seed >> (bit % 31)) & 1) == 1;
        bit++;
        filled[row][col] = on;
        filled[row][cells - 1 - col] = on; // mirror
        if (on) {
          anyFilled = true;
        } else {
          anyEmpty = true;
        }
      }
    }

    // Guarantee some shape if the pattern came out all-empty or all-full.
    if (!anyFilled || !anyEmpty) {
      filled[2][2] = !filled[2][2];
    }

    for (var row = 0; row < cells; row++) {
      for (var col = 0; col < cells; col++) {
        if (!filled[row][col]) continue;
        final rect = Rect.fromLTWH(
          origin + col * cellSize,
          origin + row * cellSize,
          cellSize,
          cellSize,
        );
        canvas.drawRRect(RRect.fromRectAndRadius(rect, blockRadius), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IdenticonPainter oldDelegate) {
    return oldDelegate.seed != seed;
  }
}
