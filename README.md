# Sudoku Flutter App (MVP)

A minimal, clean Sudoku game built with Flutter for Android (and later iOS).

## Features
- 9x9 Sudoku grid with clear 3x3 box borders
- Pre-filled cells are locked
- Tap to select a cell
- Number pad for input
- Local validation (row, column, box)
- Detects when puzzle is solved
- Minimal, modern UI

## Project Structure
```
lib/
  main.dart
  screens/
    game_screen.dart
  widgets/
    sudoku_grid.dart
    number_pad.dart
  models/
    sudoku_board.dart
  logic/
    sudoku_validator.dart
```

## Setup Instructions (Windows)

### 1. Install Flutter
- Download and install Flutter: https://docs.flutter.dev/get-started/install/windows
- Add Flutter to your PATH
- Run `flutter doctor` in a terminal to check setup

### 2. Set Up VSCode
- Install the [Flutter extension](https://marketplace.visualstudio.com/items?itemName=Dart-Code.flutter) in VSCode
- (Optional) Install the [Dart extension](https://marketplace.visualstudio.com/items?itemName=Dart-Code.dart)

### 3. Create the Project
If not already done:
```
flutter create sudoku
cd sudoku
```

### 4. Add the Provided Code
- Replace the contents of the `lib/` folder with the files in this repo.

### 5. Run the App
- Start an Android emulator or connect a physical Android device
- In the project root, run:
```
flutter run
```

The app should launch on your device/emulator.

---

**Note:**
- No multiplayer, backend, or rating features are included in this MVP.
- All logic and validation are local.

For future steps, multiplayer and backend features will be added.
