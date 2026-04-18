import 'package:flutter/material.dart';
import '../models/sudoku_board.dart';
import 'sudoku_cell.dart';

class SudokuGrid extends StatelessWidget {
  final SudokuBoard board;
  final int? selectedRow;
  final int? selectedCol;
  final void Function(int, int) onCellTap;
  final Set<String> invalidCells;
  final Map<String, Set<int>> notes;
  final bool isDarkMode;

  const SudokuGrid({
    Key? key,
    required this.board,
    required this.selectedRow,
    required this.selectedCol,
    required this.onCellTap,
    this.invalidCells = const {},
    this.notes = const {},
    this.isDarkMode = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDarkMode ? const Color(0xFF111827) : Colors.white,
      child: Column(
        children: List.generate(9, (row) {
          return Expanded(
            child: Row(
              children: List.generate(9, (col) {
                final isSelected = selectedRow == row && selectedCol == col;
                final isLocked = board.isCellLocked(row, col);
                final value = board.current[row][col];
                final isRowHighlighted =
                    selectedRow != null && row == selectedRow && !isSelected;
                final isColHighlighted =
                    selectedCol != null && col == selectedCol && !isSelected;
                final isInvalid = invalidCells.contains('$row-$col');
                final cellNotes = notes['$row-$col'] ?? const <int>{};
                double top = row == 0 ? 3 : (row % 3 == 0 ? 2 : 0.5);
                double left = col == 0 ? 3 : (col % 3 == 0 ? 2 : 0.5);
                double right = col == 8 ? 3 : 0.5;
                double bottom = row == 8 ? 3 : 0.5;
                final borderColor =
                    isDarkMode ? const Color(0xFF64748B) : Colors.black;
                return Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(width: top, color: borderColor),
                        left: BorderSide(width: left, color: borderColor),
                        right: BorderSide(width: right, color: borderColor),
                        bottom: BorderSide(width: bottom, color: borderColor),
                      ),
                    ),
                    child: SudokuCell(
                      value: value,
                      isLocked: isLocked,
                      isSelected: isSelected,
                      isRowHighlighted: isRowHighlighted,
                      isColHighlighted: isColHighlighted,
                      isInvalid: isInvalid,
                      notes: cellNotes,
                      isDarkMode: isDarkMode,
                      onTap: () => onCellTap(row, col),
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      ),
    );
  }
}
