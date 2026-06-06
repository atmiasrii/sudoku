import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/rankings_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const SudokuApp());
}

class SudokuApp extends StatefulWidget {
  const SudokuApp({super.key});

  @override
  State<SudokuApp> createState() => _SudokuAppState();
}

class _SudokuAppState extends State<SudokuApp> {
  bool _showSplash = true;
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

  Widget _buildMainScaffold() {
    final pages = [
      HomeScreen(
        highlightMistakes: _highlightMistakes,
        timerEnabled: _timerEnabled,
        onSettingsPressed: () => setState(() => _selectedTab = 3),
      ),
      const RankingsScreen(),
      const ProfileScreen(),
      SettingsScreen(
        darkMode: _darkMode,
        highlightMistakes: _highlightMistakes,
        timerEnabled: _timerEnabled,
        soundEffects: _soundEffects,
        onDarkModeChanged: (v) {
          setState(() => _darkMode = v);
          _setBool('darkMode', v);
        },
        onHighlightMistakesChanged: (v) {
          setState(() => _highlightMistakes = v);
          _setBool('highlightMistakes', v);
        },
        onTimerChanged: (v) {
          setState(() => _timerEnabled = v);
          _setBool('timerEnabled', v);
        },
        onSoundEffectsChanged: (v) {
          setState(() => _soundEffects = v);
          _setBool('soundEffects', v);
        },
        onNavigateToHome: () => setState(() => _selectedTab = 0),
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedTab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (i) => setState(() => _selectedTab = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primaryFixed,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.leaderboard_outlined),
            selectedIcon: Icon(Icons.leaderboard),
            label: 'Rankings',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sudoku Royale',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          surface: AppColors.surface,
          onSurface: AppColors.onSurface,
          primaryContainer: AppColors.primaryFixed,
          onPrimaryContainer: AppColors.primary,
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
        navigationBarTheme: NavigationBarThemeData(
          labelTextStyle: WidgetStatePropertyAll(
            GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        scaffoldBackgroundColor: AppColors.surface,
      ),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      home: _showSplash
          ? SplashScreen(onComplete: () => setState(() => _showSplash = false))
          : _buildMainScaffold(),
    );
  }
}
