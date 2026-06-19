import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import '../../app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/game_api_service.dart';
import '../../utils/validators.dart';
import 'auth_widgets.dart';

enum _AuthMode { login, signup }

/// One screen for both login and sign-up, toggled in place (no route pushes).
/// Pushing a separate signup route used to leave it stranded on top of the app
/// after auth succeeded — a single screen that the AuthGate swaps out wholesale
/// removes that whole class of bug.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _AuthMode _mode = _AuthMode.login;

  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _usernameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  // Per-field errors (shown directly below each field). A field starts
  // validating on blur, then live-validates once it has errored ("reward early,
  // punish late") so a fix clears the message instantly.
  String? _usernameError;
  String? _emailError;
  String? _passwordError;
  bool _usernameTouched = false;
  bool _emailTouched = false;
  bool _passwordTouched = false;

  // Errors not tied to a single field (network, unknown) + the email-confirm
  // info message.
  String? _formError;
  String? _info;

  bool _loading = false;
  bool _obscurePassword = true;

  bool get _isSignup => _mode == _AuthMode.signup;

  @override
  void initState() {
    super.initState();
    _usernameFocus.addListener(() {
      if (!_usernameFocus.hasFocus) _validateUsername(markTouched: true);
    });
    _emailFocus.addListener(() {
      if (!_emailFocus.hasFocus) _validateEmail(markTouched: true);
    });
    _passwordFocus.addListener(() {
      if (!_passwordFocus.hasFocus) _validatePassword(markTouched: true);
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _switchMode(_AuthMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _formError = null;
      _info = null;
      _usernameError = null;
      _emailError = null;
      _passwordError = null;
      _usernameTouched = false;
      _emailTouched = false;
      _passwordTouched = false;
    });
  }

  // --- Field validation -----------------------------------------------------

  bool _validateUsername({bool markTouched = false}) {
    if (!_isSignup) return true;
    if (markTouched) _usernameTouched = true;
    final err = AccountValidators.usernameError(_usernameController.text.trim());
    if (_usernameTouched) setState(() => _usernameError = err);
    return err == null;
  }

  bool _validateEmail({bool markTouched = false}) {
    if (markTouched) _emailTouched = true;
    final value = _emailController.text.trim();
    String? err;
    if (value.isEmpty) {
      err = 'Enter your email.';
    } else if (!value.contains('@') || !value.contains('.')) {
      err = 'Enter a valid email address.';
    }
    if (_emailTouched) setState(() => _emailError = err);
    return err == null;
  }

  bool _validatePassword({bool markTouched = false}) {
    if (markTouched) _passwordTouched = true;
    final value = _passwordController.text;
    String? err;
    if (value.isEmpty) {
      err = 'Enter your password.';
    } else if (_isSignup) {
      // Strength rules only apply when creating an account.
      err = AccountValidators.passwordError(value);
    }
    if (_passwordTouched) setState(() => _passwordError = err);
    return err == null;
  }

  // --- Submit ---------------------------------------------------------------

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _formError = null;
      _info = null;
    });

    // Force-touch so empty fields surface their errors on submit.
    final okUsername = _validateUsername(markTouched: true);
    final okEmail = _validateEmail(markTouched: true);
    final okPassword = _validatePassword(markTouched: true);
    if (!okUsername || !okEmail || !okPassword) return;

    setState(() => _loading = true);
    try {
      if (_isSignup) {
        await _doSignup();
      } else {
        await AuthService.instance.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        // AuthGate swaps to the app automatically on success.
      }
    } catch (e) {
      if (!mounted) return;
      _applyAuthError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _doSignup() async {
    final username = _usernameController.text.trim();
    // Pre-check the username so we don't create an auth account that then can't
    // claim its name. The unique DB index is the final guard on a race.
    final available = await GameApiService.isUsernameAvailable(username);
    if (!available) {
      if (!mounted) return;
      setState(() {
        _usernameTouched = true;
        _usernameError = 'That username is already taken. Try another.';
      });
      return;
    }

    await AuthService.instance.signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      username: username,
    );
    if (!mounted) return;
    // If email confirmation is ON, there is no session yet — tell the user.
    if (AuthService.instance.currentSession == null) {
      setState(() => _info =
          'Account created. Check your email to confirm, then sign in.');
    }
    // If confirmation is OFF, AuthGate swaps to the app automatically.
  }

  /// Map an auth exception to the most specific field possible (research: tell
  /// the user *which* field is wrong), falling back to a form-level message.
  /// Never clears what the user typed.
  void _applyAuthError(Object e) {
    final s = e.toString();
    final lower = s.toLowerCase();

    if (lower.contains('already registered') ||
        lower.contains('already been registered') ||
        lower.contains('user already exists')) {
      setState(() {
        _emailTouched = true;
        _emailError = 'That email is already registered. Sign in instead.';
      });
      return;
    }
    if (lower.contains('weak') ||
        lower.contains('pwned') ||
        lower.contains('compromised') ||
        lower.contains('password should be')) {
      setState(() {
        _passwordTouched = true;
        _passwordError =
            'Choose a stronger password — at least 8 characters and not a common or breached one.';
      });
      return;
    }
    if (lower.contains('invalid login credentials')) {
      // On login, don't reveal which field is wrong.
      setState(() => _formError = 'Wrong email or password.');
      return;
    }
    if (lower.contains('username_taken')) {
      setState(() {
        _usernameTouched = true;
        _usernameError = 'That username is already taken. Try another.';
      });
      return;
    }
    if (s.contains('SocketException') || s.contains('Failed host lookup')) {
      setState(() => _formError = 'No connection. Check your network.');
      return;
    }
    setState(() => _formError =
        _isSignup ? 'Could not create account. Try again.' : 'Could not sign in. Try again.');
  }

  // --- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AuthBrand(
                    subtitle:
                        _isSignup ? 'Create your account' : 'Sign in to compete',
                  ),
                  const SizedBox(height: 28),
                  _ModeToggle(mode: _mode, onChanged: _loading ? null : _switchMode),
                  const SizedBox(height: 24),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SizeTransition(
                        sizeFactor: anim,
                        axisAlignment: -1,
                        child: child,
                      ),
                    ),
                    child: Column(
                      key: ValueKey(_mode),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _buildFields(),
                    ),
                  ),
                  if (_formError != null) ...[
                    const SizedBox(height: 16),
                    AuthErrorBox(message: _formError!),
                  ],
                  if (_info != null) ...[
                    const SizedBox(height: 16),
                    AuthInfoBox(message: _info!),
                  ],
                  const SizedBox(height: 24),
                  AuthPrimaryButton(
                    label: _isSignup ? 'Create Account' : 'Sign In',
                    loading: _loading,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFields() {
    return [
      if (_isSignup) ...[
        PostHogMaskWidget(
          child: _Field(
            controller: _usernameController,
            focusNode: _usernameFocus,
            label: 'Username',
            hint: 'Shown on the leaderboard',
            icon: Icons.person_outline,
            errorText: _usernameError,
            autofillHints: const [AutofillHints.newUsername],
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_usernameTouched) _validateUsername();
            },
            onSubmitted: (_) => _emailFocus.requestFocus(),
          ),
        ),
        const SizedBox(height: 16),
      ],
      PostHogMaskWidget(
        child: _Field(
          controller: _emailController,
          focusNode: _emailFocus,
          label: 'Email',
          hint: 'you@example.com',
          icon: Icons.mail_outline,
          errorText: _emailError,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            if (_emailTouched) _validateEmail();
          },
          onSubmitted: (_) => _passwordFocus.requestFocus(),
        ),
      ),
      const SizedBox(height: 16),
      PostHogMaskWidget(
        child: _Field(
          controller: _passwordController,
          focusNode: _passwordFocus,
          label: 'Password',
          hint: _isSignup ? 'At least 8 characters' : '••••••••',
          icon: Icons.lock_outline,
          errorText: _passwordError,
          obscure: _obscurePassword,
          autofillHints: _isSignup
              ? const [AutofillHints.newPassword]
              : const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          suffix: IconButton(
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: AppColors.outline,
              size: 20,
            ),
          ),
          onChanged: (_) {
            if (_passwordTouched) _validatePassword();
          },
          onSubmitted: (_) => _submit(),
        ),
      ),
    ];
  }
}

/// Segmented Login / Sign-up toggle.
class _ModeToggle extends StatelessWidget {
  final _AuthMode mode;
  final ValueChanged<_AuthMode>? onChanged;

  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _segment('Sign In', _AuthMode.login),
          _segment('Sign Up', _AuthMode.signup),
        ],
      ),
    );
  }

  Widget _segment(String label, _AuthMode value) {
    final selected = mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.onSurfaceVariant,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Labelled text field with an error line below it, optional suffix, and a
/// valid/invalid coloured border.
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final IconData icon;
  final String? errorText;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final List<String>? autofillHints;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const _Field({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    required this.icon,
    this.errorText,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.autofillHints,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.outline,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscure,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          autofillHints: autofillHints,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: const TextStyle(
            color: AppColors.onSurface,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: AppColors.outlineVariant,
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: Icon(icon, color: AppColors.outline, size: 20),
            suffixIcon: suffix,
            filled: true,
            fillColor: AppColors.surfaceContainerLowest,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: hasError
                    ? AppColors.error
                    : AppColors.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: hasError ? AppColors.error : AppColors.primary,
                width: 1.5,
              ),
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: AppColors.error, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    errorText!,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
