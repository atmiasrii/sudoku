import 'package:supabase_flutter/supabase_flutter.dart';

import 'analytics_service.dart';
import 'game_api_service.dart';

/// Thin wrapper over Supabase Auth. The Supabase user id (a UUID) becomes the
/// app's canonical userId everywhere — replacing the old locally-generated UUID
/// that anyone could spoof.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final SupabaseClient _client = Supabase.instance.client;

  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;
  String? get currentUserId => _client.auth.currentUser?.id;

  /// Bearer token to send to the backend (REST header + socket auth).
  String? get accessToken => _client.auth.currentSession?.accessToken;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<void> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    final res = await _client.auth.signUp(
      email: email,
      password: password,
      data: {'username': username},
    );
    final user = res.user;
    if (user != null) {
      // Mirror into the backend `users` table so rating/stats/leaderboard work.
      await GameApiService.ensureUserProfile(
        user.id,
        username,
        accessToken: _client.auth.currentSession?.accessToken,
      );
      Analytics.capture('signed_up');
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    final res = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final user = res.user;
    if (user != null) {
      final username =
          (user.userMetadata?['username'] as String?) ?? _emailPrefix(user.email);
      // Derived/fallback username — let the backend suffix a clash so login
      // never hard-fails on a name collision.
      await GameApiService.ensureUserProfile(
        user.id,
        username,
        accessToken: _client.auth.currentSession?.accessToken,
        allowSuffix: true,
      );
      Analytics.capture('logged_in');
    }
  }

  Future<void> signOut() async {
    Analytics.capture('logged_out');
    await Analytics.reset();
    await _client.auth.signOut();
  }

  Future<void> updatePassword(String newPassword) =>
      _client.auth.updateUser(UserAttributes(password: newPassword));

  Future<void> updateEmail(String newEmail) =>
      _client.auth.updateUser(UserAttributes(email: newEmail));

  String displayName() {
    final user = currentUser;
    if (user == null) return 'Player';
    final meta = user.userMetadata?['username'] as String?;
    if (meta != null && meta.isNotEmpty) return meta;
    return _emailPrefix(user.email);
  }

  String _emailPrefix(String? email) {
    if (email == null || email.isEmpty) return 'Player';
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }
}
