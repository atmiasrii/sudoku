import 'package:flutter/material.dart';

class SudokuCell extends StatelessWidget {
  final int value;
  final bool isLocked;
  final bool isSelected;
  final bool isRowHighlighted;
  final bool isColHighlighted;
  final bool isInvalid;
  final Set<int> notes;
  final bool isDarkMode;
  final VoidCallback? onTap;

  const SudokuCell({
    Key? key,
    required this.value,
    required this.isLocked,
    required this.isSelected,
    required this.isRowHighlighted,
    required this.isColHighlighted,
    required this.isInvalid,
    this.notes = const <int>{},
    required this.isDarkMode,
    this.onTap,
  }) : super(key: key);

  Widget _buildNotesGrid(Color textColor) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: GridView.count(
        crossAxisCount: 3,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
        children: List.generate(9, (index) {
          final number = index + 1;
          return Center(
            child: notes.contains(number)
                ? Text(
                    '$number',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: textColor.withValues(alpha: 0.85),
                    ),
                  )
                : const SizedBox.shrink(),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color bgColor = isDarkMode ? const Color(0xFF111827) : Colors.transparent;
    if (isInvalid) {
      bgColor = isDarkMode ? const Color(0xFF7F1D1D) : Colors.red.shade100;
    } else if (isSelected) {
      bgColor =
          isDarkMode ? const Color(0xFF1D4ED8) : Colors.lightBlue.shade100;
    } else if (isRowHighlighted || isColHighlighted) {
      bgColor = isDarkMode
          ? const Color(0xFF1E3A8A)
          : Colors.blue.shade50.withValues(alpha: 0.5);
    }

    final textColor = isLocked
        ? (isDarkMode ? Colors.blueGrey.shade100 : Colors.black87)
        : (isDarkMode ? Colors.lightBlue.shade200 : Colors.blue.shade700);

    return GestureDetector(
      onTap: isLocked ? null : onTap,
      child: Container(
        color: bgColor,
        child: Center(
          child: value == 0
              ? (notes.isNotEmpty ? _buildNotesGrid(textColor) : null)
              : Text(
                  value.toString(),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: isLocked ? FontWeight.bold : FontWeight.normal,
                    color: textColor,
                  ),
                ),
        ),
      ),
    );
  }
}
