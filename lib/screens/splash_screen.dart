import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _opacity;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _opacity = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut),
    );
    _animCtrl.forward();

    Future.delayed(const Duration(milliseconds: 2800), () {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: FadeTransition(
            opacity: _opacity,
            child: ScaleTransition(
              scale: _scale,
              child: const _SudokuRoyaleLogo(),
            ),
          ),
        ),
      ),
    );
  }
}

class _SudokuRoyaleLogo extends StatelessWidget {
  const _SudokuRoyaleLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        SizedBox(
          width: 200,
          height: 200,
          child: CustomPaint(painter: _SudokuLogoPainter()),
        ),
        SizedBox(height: 26),
        Text(
          'SUDOKU ROYALE',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w400,
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }
}

/// Draws the app-logo sudoku board (matches the launcher icon): a white rounded
/// 4x4 board with thin inner lines, a bold 2x2 sub-box divider, a bold outer
/// frame, and the fixed numbers (2 / 4,0 / -- / 6,9).
class _SudokuLogoPainter extends CustomPainter {
  const _SudokuLogoPainter();

  static const _ink = Color(0xFF1A1A1A);
  static const _numbers = [
    [0, 1, '2'],
    [1, 0, '4'],
    [1, 2, '0'],
    [3, 1, '6'],
    [3, 2, '9'],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final board = size.width;
    final radius = Radius.circular(board * 0.14);
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, radius);

    // White board.
    canvas.drawRRect(rrect, Paint()..color = Colors.white);

    final cell = board / 4;
    final thin = board * 0.012;
    final thick = board * 0.030;
    final line = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke;

    canvas.save();
    canvas.clipRRect(rrect);

    // Thin inner grid lines.
    line.strokeWidth = thin;
    for (final i in [1, 3]) {
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, board), line);
      canvas.drawLine(Offset(0, i * cell), Offset(board, i * cell), line);
    }
    // Bold middle 2x2 divider.
    line.strokeWidth = thick;
    canvas.drawLine(Offset(2 * cell, 0), Offset(2 * cell, board), line);
    canvas.drawLine(Offset(0, 2 * cell), Offset(board, 2 * cell), line);
    canvas.restore();

    // Bold rounded outer frame.
    final inset = thick / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(inset, inset, board - thick, board - thick),
        Radius.circular(board * 0.14 - inset),
      ),
      line..strokeWidth = thick,
    );

    // Numbers.
    for (final n in _numbers) {
      final row = n[0] as int;
      final col = n[1] as int;
      final value = n[2] as String;
      final tp = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            color: _ink,
            fontSize: cell * 0.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          col * cell + (cell - tp.width) / 2,
          row * cell + (cell - tp.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SudokuLogoPainter oldDelegate) => false;
}
