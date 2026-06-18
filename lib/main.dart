import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_colors.dart';
import 'config/analytics_config.dart';
import 'config/supabase_config.dart';
import 'services/analytics_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/game_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/rankings_screen.dart';
import 'screens/splash_screen.dart';
import 'services/active_game_store.dart';
import 'services/auth_service.dart';
import 'widgets/app_settings_sheet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  // Product analytics. No-ops entirely when POSTHOG_KEY isn't passed at build.
  if (AnalyticsConfig.enabled) {
    final config = PostHogConfig(AnalyticsConfig.key)
      ..host = AnalyticsConfig.host
      ..captureApplicationLifecycleEvents = true;
    await Posthog().setup(config);
  }
  await Analytics.init();

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

  void _openSettingsSheet(BuildContext context) {
    showAppSettingsSheet(
      context,
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
    );
  }

  Widget _buildMainScaffold(String userId) {
    return MainShell(
      userId: userId,
      highlightMistakes: _highlightMistakes,
      timerEnabled: _timerEnabled,
      onOpenSettings: _openSettingsSheet,
    );
  }

  @override
  Widget build(BuildContext context) {
    // PostHogWidget enables tap/gesture autocapture across the whole tree;
    // PosthogObserver autocaptures every screen/route navigation.
    return PostHogWidget(
      child: MaterialApp(
        title: 'Sudoku Royale',
        debugShowCheckedModeBanner: false,
        navigatorObservers: [if (AnalyticsConfig.enabled) PosthogObserver()],
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
            ? SplashScreen(
                onComplete: () => setState(() => _showSplash = false))
            : _AuthGate(buildMainScaffold: _buildMainScaffold),
      ),
    );
  }
}

/// Gates the app behind Supabase auth. Rebuilds whenever the auth state
/// changes (sign in / sign out / token refresh) and shows either the login
/// screen or the main app keyed to the authenticated user's id.
///
/// A real Supabase account is REQUIRED — the backend enforces
/// SUPABASE_JWT_SECRET, so every REST call and socket needs a valid token.
/// There is no guest bypass.
class _AuthGate extends StatefulWidget {
  final Widget Function(String userId) buildMainScaffold;

  const _AuthGate({required this.buildMainScaffold});

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  String? _identifiedId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: AuthService.instance.onAuthStateChange,
      builder: (context, snapshot) {
        final userId = AuthService.instance.currentUserId;
        if (userId == null) {
          return const LoginScreen();
        }
        // Tie analytics events to this user once per identity change.
        if (userId != _identifiedId) {
          _identifiedId = userId;
          Analytics.identify(userId);
        }
        return widget.buildMainScaffold(userId);
      },
    );
  }
}

/// The 3-tab main app shell. Also checks on first build whether a game was left
/// in progress (app killed / network lost mid-match) and offers to resume it.
class MainShell extends StatefulWidget {
  final String userId;
  final bool highlightMistakes;
  final bool timerEnabled;
  final void Function(BuildContext context) onOpenSettings;

  const MainShell({
    super.key,
    required this.userId,
    required this.highlightMistakes,
    required this.timerEnabled,
    required this.onOpenSettings,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedTab = 0;
  bool _resumeChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeResumeGame());
  }

  Future<void> _maybeResumeGame() async {
    if (_resumeChecked) return;
    _resumeChecked = true;

    final snapshot = await ActiveGameStore.load(widget.userId);
    if (snapshot == null || !mounted) return;

    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Resume Game?',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.onSurface),
        ),
        content: const Text(
          'You left a match in progress. Pick up where you left off?',
          style: TextStyle(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Discard'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Resume'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (resume != true) {
      await ActiveGameStore.clear();
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameScreen(
          restoreFrom: snapshot,
          highlightMistakes: widget.highlightMistakes,
          timerEnabled: widget.timerEnabled,
          currentUserId: widget.userId,
          multiplayerEnabled: snapshot.multiplayer,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        userId: widget.userId,
        highlightMistakes: widget.highlightMistakes,
        timerEnabled: widget.timerEnabled,
        onSettingsPressed: () => widget.onOpenSettings(context),
      ),
      RankingsScreen(
        userId: widget.userId,
        onSettingsPressed: () => widget.onOpenSettings(context),
      ),
      ProfileScreen(
        userId: widget.userId,
        onSettingsPressed: () => widget.onOpenSettings(context),
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedTab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (i) {
          setState(() => _selectedTab = i);
          Analytics.capture('tab_changed', props: {
            'tab': const ['home', 'rankings', 'profile'][i],
          });
        },
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
        ],
      ),
    );
  }
}
