/// Client-side input validation for account creation. These are UX guards —
/// the authoritative checks live server-side (Supabase password policy +
/// leaked-password protection, and the case-insensitive unique username index).
///
/// Password policy follows NIST 800-63B: a reasonable minimum length and no
/// forced composition; breached passwords are rejected by Supabase.
class AccountValidators {
  AccountValidators._();

  static const int minPasswordLength = 8;

  static final RegExp _usernameRe = RegExp(r'^[A-Za-z0-9_.-]{3,20}$');

  /// Returns an error message, or null if the password is acceptable.
  static String? passwordError(String password) {
    if (password.length < minPasswordLength) {
      return 'Password must be at least $minPasswordLength characters.';
    }
    return null;
  }

  /// Returns an error message, or null if the username is acceptable.
  static String? usernameError(String username) {
    if (username.isEmpty) return 'Choose a username.';
    if (!_usernameRe.hasMatch(username)) {
      return 'Username must be 3-20 letters, numbers, _ . or -';
    }
    return null;
  }
}
