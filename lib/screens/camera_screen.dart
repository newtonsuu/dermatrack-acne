import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_theme.dart';
import '../widgets/user_avatar_action.dart';

/// Camera screen for capturing a selfie used in a skin scan.
///
/// v1 uses `image_picker` for simplicity — it shells out to the platform's
/// system camera UI, which handles permissions, focus, and saving. In a later
/// pass we can swap to the `camera` plugin for an in-app viewfinder with
/// face/lighting guidance overlays.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final ImagePicker _picker = ImagePicker();
  // Hold raw bytes instead of a dart:io File so the screen works on web,
  // mobile, and desktop. XFile.readAsBytes() is cross-platform; File isn't.
  Uint8List? _capturedImageBytes;
  bool _isPicking = false;
  String? _errorMessage;

  Future<void> _takePhoto() async {
    setState(() {
      _isPicking = true;
      _errorMessage = null;
    });
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 90,
        maxWidth: 1600,
      );
      if (!mounted) return;
      if (photo != null) {
        final bytes = await photo.readAsBytes();
        if (!mounted) return;
        setState(() => _capturedImageBytes = bytes);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Could not open the camera: $e');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _pickFromGallery() async {
    setState(() {
      _isPicking = true;
      _errorMessage = null;
    });
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1600,
      );
      if (!mounted) return;
      if (photo != null) {
        final bytes = await photo.readAsBytes();
        if (!mounted) return;
        setState(() => _capturedImageBytes = bytes);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Could not open the gallery: $e');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _retake() {
    setState(() => _capturedImageBytes = null);
  }

  void _useThisPhoto() {
    // Placeholder — wires to ScanService when the API integration lands.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved! Analysis pipeline coming soon.'),
      ),
    );
    setState(() => _capturedImageBytes = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: const Text('New scan'),
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        actions: const [UserAvatarAction()],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _capturedImageBytes == null
              ? _buildEmptyState()
              : _buildPreview(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.border(context)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    color: AppTheme.primary,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Capture your selfie',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Find good lighting, face the camera, and hold it about 25–35 cm away.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 24),
                const _TipRow(icon: Icons.wb_sunny_outlined, text: 'Bright, even lighting'),
                const SizedBox(height: 8),
                const _TipRow(icon: Icons.face_outlined, text: 'Whole face in frame'),
                const SizedBox(height: 8),
                const _TipRow(icon: Icons.blur_off_outlined, text: 'Hold steady — no blur'),
              ],
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            style: TextStyle(color: Colors.red.shade700),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _isPicking ? null : _takePhoto,
          icon: const Icon(Icons.camera_alt),
          label: Text(_isPicking ? 'Opening…' : 'Open camera'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _isPicking ? null : _pickFromGallery,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Choose from gallery'),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.memory(
              _capturedImageBytes!,
              fit: BoxFit.cover,
              width: double.infinity,
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _useThisPhoto,
          icon: const Icon(Icons.check),
          label: const Text('Use this photo'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _retake,
          icon: const Icon(Icons.refresh),
          label: const Text('Retake'),
        ),
      ],
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppTheme.textSecondary(context)),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: AppTheme.textSecondary(context))),
      ],
    );
  }
}
