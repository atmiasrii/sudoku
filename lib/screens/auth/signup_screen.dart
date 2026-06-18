import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import '../../app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/game_api_service.dart';
import '../../utils/validators.dart';
import 'auth_widgets.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Fill in every field.');
      return;
    }
    final usernameErr = AccountValidators.usernameError(username);
    if (usernameErr != null) {
      setState(() => _error = usernameErr);
      return;
    }
    final passwordErr = AccountValidators.passwordError(password);
    if (passwordErr != null) {
      setState(() => _error = passwordErr);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });

    try {
      // Pre-check the username so we don't create an auth account that then
      // can't claim its name. The unique DB index is the final guard on a race.
      final available = await GameApiService.isUsernameAvailable(username);
      if (!available) {
        if (!mounted) return;
        setState(() {
          _error = 'That username is already taken. Try another.';
          _loading = false;
        });
        return;
      }

      await AuthService.instance
          .signUp(email: email, password: password, username: username);
      if (!mounted) return;
      // If email confirmation is ON, there is no session yet — tell the user.
      if (AuthService.instance.currentSession == null) {
        setState(() =>
            _info = 'Account created. Check your email to confirm, then sign in.');
      }
      // If confirmation is OFF, AuthGate swaps to the app automatically.
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        foregroundColor: AppColors.primary,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AuthBrand(subtitle: 'Create your account'),
                const SizedBox(height: 32),
                PostHogMaskWidget(
                  child: AuthTextField(
                    controller: _usernameController,
                    label: 'Username',
                    hint: 'Shown on the leaderboard',
                    icon: Icons.person_outline,
                  ),
                ),
                const SizedBox(height: 16),
                PostHogMaskWidget(
                  child: AuthTextField(
                    controller: _emailController,
                    label: 'Email',
                    hint: 'you@example.com',
                    keyboardType: TextInputType.emailAddress,
                    icon: Icons.mail_outline,
                  ),
                ),
                const SizedBox(height: 16),
                PostHogMaskWidget(
                  child: AuthTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hint: 'At least 6 characters',
                    obscure: true,
                    icon: Icons.lock_outline,
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  AuthErrorBox(message: _error!),
                ],
                if (_info != null) ...[
                  const SizedBox(height: 16),
                  AuthInfoBox(message: _info!),
                ],
                const SizedBox(height: 28),
                AuthPrimaryButton(
                  label: 'Create Account',
                  loading: _loading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 18),
                AuthFooterLink(
                  leading: 'Already have an account?',
                  action: 'Sign in',
                  onTap: _loading ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    final lower = s.toLowerCase();
    if (s.contains('already registered') || s.contains('already been registered')) {
      return 'That email is already registered.';
    }
    // Supabase rejects weak / known-breached passwords (leaked-password
    // protection) with messages mentioning "weak", "pwned", or a length rule.
    if (lower.contains('weak') ||
        lower.contains('pwned') ||
        lower.contains('compromised') ||
        lower.contains('password should be')) {
      return 'Choose a stronger password — at least 8 characters and not a common or breached one.';
    }
    if (s.contains('SocketException') || s.contains('Failed host lookup')) {
      return 'No connection. Check your network.';
    }
    return 'Could not create account. Try again.';
  }
}
