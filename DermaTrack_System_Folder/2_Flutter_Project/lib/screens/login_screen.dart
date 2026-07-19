import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/brand_logo.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.accessLabel = 'Patient',
    this.showRegister = true,
  });

  /// Which access type the user picked on the "Login as" screen. Themes the
  /// subtitle; the actual role is still enforced by the account in the
  /// database after sign-in.
  final String accessLabel;

  /// Whether to show the "Register here" link (patients only).
  final bool showRegister;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Server-side errors keyed by field. Cleared when the user edits that field.
  String? _emailError;
  String? _passwordError;

  bool _isSubmitting = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(() {
      if (_emailError != null) setState(() => _emailError = null);
    });
    _passwordController.addListener(() {
      if (_passwordError != null) setState(() => _passwordError = null);
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _emailError = null;
      _passwordError = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    final result = await AuthService.instance.signIn(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (!mounted) return;
    if (result == null) {
      // Success — AuthGate has swapped the underlying route to HomeShell.
      // Pop back to the root so the user lands on the dashboard, not on this
      // screen sitting on top of HomeShell.
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    setState(() {
      _isSubmitting = false;
      if (result.field == AuthField.email) {
        _emailError = result.message;
      } else if (result.field == AuthField.password) {
        _passwordError = result.message;
      }
      // Re-run validators so the error message shows under the right field.
      _formKey.currentState?.validate();
    });
  }

  void _openRegister() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
  }

  void _openForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          initialEmail: _emailController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const BrandLogo(),
                    const SizedBox(height: 24),
                    Text(
                      'Welcome back',
                      style: Theme.of(context).textTheme.headlineLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.accessLabel == 'Patient'
                          ? 'Sign in to continue tracking your skin.'
                          : 'Sign in to your ${widget.accessLabel} account.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Email is required.';
                        }
                        // Allow multi-label domains (e.g. mymail.mapua.edu.ph).
                        final emailRegex = RegExp(r'^[\w.\-]+@([\w\-]+\.)+[a-zA-Z]{2,}$');
                        if (!emailRegex.hasMatch(value.trim())) {
                          return 'Please enter a valid email address.';
                        }
                        return _emailError; // null when no server error
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Password is required.';
                        }
                        return _passwordError;
                      },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _isSubmitting ? null : _openForgotPassword,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Forgot password?'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Sign in'),
                    ),
                    if (widget.showRegister) ...[
                      const SizedBox(height: 20),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'No account yet?',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          TextButton(
                            onPressed: _isSubmitting ? null : _openRegister,
                            child: const Text('Register here'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
