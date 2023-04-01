import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/face_detection_service.dart';
import '../services/scan_service.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar_action.dart';
import 'scan_detail_screen.dart';

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
  bool _isSubmitting = false;
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
    if (_isSubmitting) return;
    setState(() => _capturedImageBytes = null);
  }

  /// Sends the captured selfie to ScanService for upload + analysis.
  ///
  /// Runs a preflight face-detection check first (on-device, ~200ms). If
  /// the check fails — no face, multiple faces, face too small, face too
  /// tilted — submission is blocked with the failure reason. Saves a
  /// 5-second Edge Function round-trip + a wasted Roboflow / HF call on
  /// garbage inputs, and matches AcneCheck's "chair photo defense"
  /// methodology contribution.
  ///
  /// On Flutter Web the preflight skips (ML Kit isn't available) — survey
  /// respondents get the unguarded flow as a phase-1 limitation.
  ///
  /// On success, pushes the scan-detail screen and clears the preview so
  /// the camera screen is ready for the next scan.
  Future<void> _useThisPhoto() async {
    final bytes = _capturedImageBytes;
    if (bytes == null || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      // Preflight — block submission for low-quality / non-face captures
      // before we waste an Edge Function call on them.
      final preflight = await FaceDetectionService.instance.check(bytes);
      if (!mounted) return;
      if (!preflight.passed) {
        setState(() {
          _isSubmitting = false;
          _errorMessage =
              preflight.userMessage ?? 'This photo didn\'t pass the quality check.';
        });
        return;
      }

      // Preflight passed (or was skipped on web) — proceed with the
      // existing upload + analysis flow.
      final scan = await ScanService.instance.submitScan(bytes);
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _capturedImageBytes = null;
      });
      // Push detail. Back button returns to the (empty) camera screen.
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ScanDetailScreen(scan: scan)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = _friendlyError(e);
      });
    }
  }

  /// Strip the leading "Exception: " from `Exception("…")` strings so the
  /// snackbar doesn't read like a stack-trace excerpt.
  String _friendlyError(Object e) {
    final s = e.toString();
    const prefix = 'Exception: ';
    return s.startsWith(prefix) ? s.substring(prefix.length) : s;
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(_capturedImageBytes!, fit: BoxFit.cover),
                if (_isSubmitting) const _AnalyzingOverlay(),
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
          onPressed: _isSubmitting ? null : _useThisPhoto,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Icon(Icons.check),
          label: Text(_isSubmitting ? 'Analyzing…' : 'Use this photo'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _isSubmitting ? null : _retake,
          icon: const Icon(Icons.refresh),
          label: const Text('Retake'),
        ),
      ],
    );
  }
}

/// Semi-transparent overlay shown on top of the preview while the scan is
/// being uploaded + analyzed. Telegraphs the cold-start possibility so a
/// 30–60 s wait doesn't feel like the app froze.
class _AnalyzingOverlay extends StatelessWidget {
  const _AnalyzingOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.55),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 38,
                height: 38,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Analyzing your skin…',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'This can take up to a minute on the first scan of the day.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
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
