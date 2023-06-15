import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../services/auth_service.dart';
import '../services/profile_service.dart';

/// Lets the signed-in user change their display name and username.
/// Username uniqueness is enforced by the `profiles.username` UNIQUE
/// constraint; collisions surface as a field error on the username input.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();

  String? _displayNameError;
  String? _usernameError;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill from current auth metadata (matches AuthService.currentUser).
    final supaUser = supa.Supabase.instance.client.auth.currentUser;
    final meta = supaUser?.userMetadata ?? const <String, dynamic>{};
    _displayNameController.text =
        (meta['display_name'] as String?)?.trim() ??
            AuthService.instance.currentUser?.displayName ??
            '';
    _usernameController.text =
        (meta['username'] as String?)?.trim() ??
            AuthService.instance.currentUser?.username ??
            '';

    _displayNameController.addListener(() {
      if (_displayNameError != null) {
        setState(() => _displayNameError = null);
      }
    });
    _usernameController.addListener(() {
      if (_usernameError != null) {
        setState(() => _usernameError = null);
      }
    });
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _displayNameError = null;
      _usernameError = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    final result = await ProfileService.instance.updateProfile(
      displayName: _displayNameController.text,
      username: _usernameController.text,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated.')),
      );
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      if (result.field == AuthField.username) {
        // Could be a uniqueness/length/empty issue — either way, surfaces
        // under the username field. Display-name issues land here too,
        // since updateProfile uses AuthField.username for both.
        _usernameError = result.message;
      } else {
        _displayNameError = result.message;
      }
      _formKey.currentState?.validate();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
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
                      controller: _displayNameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (value) {
                        final trimmed = (value ?? '').trim();
                        if (trimmed.isEmpty) {
                          return 'Display name is required.';
                        }
                        return _displayNameError;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _usernameController,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      onFieldSubmitted: (_) => _save(),
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      validator: (value) {
                        final trimmed = (value ?? '').trim();
                        if (trimmed.isEmpty) return 'Username is required.';
                        if (trimmed.length < 3) {
                          return 'Username must be at least 3 characters.';
                        }
                        return _usernameError;
                      },
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _save,
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Save changes'),
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
