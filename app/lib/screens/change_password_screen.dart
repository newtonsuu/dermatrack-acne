import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/password_strength_checklist.dart';

/// Lets the signed-in user change their password. The session is the proof
/// of identity (we don't re-prompt for the current password), since the
/// signed-in user is already trusted by Supabase's auth layer.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  final _newFocusNode = FocusNode();

  String? _newError;
  String? _confirmError;
  bool _isSubmitting = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _newController.addListener(() {
      // Rebuild so the strength checklist refreshes as the user types.
      setState(() => _newError = null);
    });
    _confirmController.addListener(() {
      if (_confirmError != null) setState(() => _confirmError = null);
    });
    _newFocusNode.addListener(() {
      // Show/hide the strength checklist with focus, matching register screen.
      setState(() {});
    });
  }

  @override
  void dispose() {
    _newController.dispose();
    _confirmController.dispose();
    _newFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _newError = null;
      _confirmError = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    final result = await AuthService.instance.changePassword(
      newPassword: _newController.text,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed.')),
      );
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      if (result.field == AuthField.password) {
        _newError = result.message;
      } else {
        _confirmError = result.message;
      }
      _formKey.currentState?.validate();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _newController,
                      focusNode: _newFocusNode,
                      obscureText: _obscureNew,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'New password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureNew
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(
                              () => _obscureNew = !_obscureNew),
                        ),
                      ),
                      validator: (value) {
                        final password = value ?? '';
                        if (password.isEmpty) {
                          return 'New password is required.';
                        }
                        if (unmetPasswordRequirements(password).isNotEmpty) {
                          return 'Password does not meet the requirements.';
                        }
                        return _newError;
                      },
                    ),
                    // Same focus-driven checklist pattern as the register
                    // screen — only visible while the password field is in
                    // focus, so the form stays uncluttered otherwise.
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      alignment: Alignment.topCenter,
                      child: _newFocusNode.hasFocus
                          ? Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: PasswordStrengthChecklist(
                                password: _newController.text,
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: _obscureConfirm,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Confirm new password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please retype your new password.';
                        }
                        if (value != _newController.text) {
                          return 'Passwords do not match.';
                        }
                        return _confirmError;
                      },
                    ),
                    const SizedBox(height: 24),
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
                          : const Text('Change password'),
                    ),
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
