import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  runApp(const SudokuApp());
}

class SudokuApp extends StatefulWidget {
  const SudokuApp({Key? key}) : super(key: key);

  @override
  State<SudokuApp> createState() => _SudokuAppState();
}

class _SudokuAppState extends State<SudokuApp> {
  bool _darkMode = false;
  bool _highlightMistakes = true;
  bool _timerEnabled = true;
  bool _soundEffects = true;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _darkMode = prefs.getBool('darkMode') ?? false;
      _highlightMistakes = prefs.getBool('highlightMistakes') ?? true;
      _timerEnabled = prefs.getBool('timerEnabled') ?? true;
      _soundEffects = prefs.getBool('soundEffects') ?? true;
    });
  }

  Future<void> _setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        highlightMistakes: _highlightMistakes,
        timerEnabled: _timerEnabled,
      ),
      const ProfileScreen(),
      SettingsScreen(
        darkMode: _darkMode,
        highlightMistakes: _highlightMistakes,
        timerEnabled: _timerEnabled,
        soundEffects: _soundEffects,
        onDarkModeChanged: (value) {
          setState(() => _darkMode = value);
          _setBool('darkMode', value);
        },
        onHighlightMistakesChanged: (value) {
          setState(() => _highlightMistakes = value);
          _setBool('highlightMistakes', value);
        },
        onTimerChanged: (value) {
          setState(() => _timerEnabled = value);
          _setBool('timerEnabled', value);
        },
        onSoundEffectsChanged: (value) {
          setState(() => _soundEffects = value);
          _setBool('soundEffects', value);
        },
      ),
    ];

    return MaterialApp(
      title: 'Sudoku',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      darkTheme: ThemeData.dark(),
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(
        body: IndexedStack(index: _selectedTab, children: pages),
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: const Color(0xFFEFF2F8),
          selectedItemColor: const Color(0xFF0E53BE),
          unselectedItemColor: const Color(0xFF4B5563),
          currentIndex: _selectedTab,
          onTap: (index) => setState(() => _selectedTab = index),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
            BottomNavigationBarItem(
                icon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
