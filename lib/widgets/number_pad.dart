import 'package:flutter/material.dart';

class NumberPad extends StatelessWidget {
  final void Function(int) onNumberInput;

  const NumberPad({Key? key, required this.onNumberInput}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 2 rows: 1-5, 6-9
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) => _buildButton(i + 1)),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (i) => _buildButton(i + 6)),
        ),
      ],
    );
  }

  Widget _buildButton(int number) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: Colors.blue.shade50,
          shape: const CircleBorder(),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => onNumberInput(number),
            child: Center(
              child: Text(
                number.toString(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
