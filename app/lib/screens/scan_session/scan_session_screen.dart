import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:uuid/uuid.dart';

import '../../models/scan.dart';
import '../../services/face_detection_service.dart';
import '../../services/region_alignment_evaluator.dart';
import '../../services/scan_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/region_overlay_painter.dart';
import 'scan_session_complete_screen.dart';

/// Guided five-step scan capture session. The dermatologist consult on
/// 2026-05-25 confirmed that regional capture (forehead → left cheek →
/// right cheek → chin → full face) is clinically more useful than a single
/// whole-face shot, because acne distribution by zone correlates with
/// underlying drivers (hormonal acne clusters on chin/jawline, mechanical
/// on cheeks, etc.).
///
/// Capture model is **camera position-driven**: the patient holds their
/// head still and moves the phone around their face. Each step shows a
/// region-specific oval template on the live preview; ML Kit's face
/// landmarks drive a real-time alignment evaluation; the capture button
/// stays disabled until alignment is locked. A long-press on the disabled
/// button bypasses the gate ("Skip alignment check") for edge cases where
/// ML Kit misfires.
///
/// All five captures share one `session_id` (a freshly-generated UUID)
/// so the UI later can present them as a coherent daily snapshot. Each
/// capture is committed to Supabase immediately on success — abandoning
/// the session midway leaves a partial set of scans in the database,
/// which is honest data rather than thrown-away work.
class ScanSessionScreen extends StatefulWidget {
  const ScanSessionScreen({super.key});

  @override
  State<ScanSessionScreen> createState() => _ScanSessionScreenState();
}

/// The order in which the guided session walks through regions. Matches
/// the dermatologist's recap (forehead, left cheek, right cheek, chin,
/// plus the whole face).
const List<ScanRegion> _sessionOrder = [
  ScanRegion.forehead,
  ScanRegion.leftCheek,
  ScanRegion.rightCheek,
  ScanRegion.chin,
  ScanRegion.fullFace,
];

class _ScanSessionScreenState extends State<ScanSessionScreen>
    with WidgetsBindingObserver {
  // ----- Camera state -----
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  CameraDescription? _activeCamera;
  bool _initializing = true;
  String? _initError;

  // ----- ML Kit / alignment state -----
  bool _processingFrame = false;
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);

  /// Throttle ML Kit calls to ~5 fps. ML Kit on a Pixel 7 takes ~50–80 ms
  /// per frame in accurate mode; cheaper than per-frame but we don't need
  /// 30 Hz feedback — the patient won't notice the difference between
  /// 5 Hz and 30 Hz hint refreshes, and 5 Hz keeps the CPU thread free.
  static const Duration _minFrameInterval = Duration(milliseconds: 200);

  /// Map from Flutter's DeviceOrientation to the rotation degrees the
  /// camera plugin reports. Used in the InputImage conversion for ML Kit.
  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  Face? _latestFace;
  int? _frameW;
  int? _frameH;
  RegionAlignmentResult _alignment = const RegionAlignmentResult(
    aligned: false,
    noFace: true,
    score: 0,
    hint: 'Position your face in the frame.',
  );

  // ----- Session state -----
  late final String _sessionId;
  int _stepIndex = 0;
  bool _capturing = false;
  bool _alignmentOverride = false;
  final List<Scan> _capturedScans = [];

  ScanRegion get _currentRegion => _sessionOrder[_stepIndex];

  bool get _captureEnabled =>
      !_capturing && (_alignment.aligned || _alignmentOverride);

  // ----- Lifecycle -----

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionId = const Uuid().v4();
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAndDisposeCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The camera surface is unhappy across backgrounding. Release on pause,
    // re-initialize on resume.
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopAndDisposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _stopAndDisposeCamera() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {/* fine */}
    try {
      await controller.dispose();
    } catch (_) {/* fine */}
  }

  Future<void> _initializeCamera() async {
    if (mounted) {
      setState(() {
        _initializing = true;
        _initError = null;
      });
    }
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _initializing = false;
            _initError = 'No camera available on this device.';
          });
        }
        return;
      }

      // Prefer the front camera for selfie scans. Fall back to first
      // available if there's no front-facing one (some tablets).
      _activeCamera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      // imageFormatGroup must match what ML Kit accepts:
      //   Android → nv21
      //   iOS     → bgra8888
      // Mismatch silently produces unusable InputImages and ML Kit fails.
      final controller = CameraController(
        _activeCamera!,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      await controller.startImageStream(_onCameraImage);

      if (mounted) {
        setState(() => _initializing = false);
      }
    } catch (e) {
      debugPrint('ScanSessionScreen.initCamera failed: $e');
      if (mounted) {
        setState(() {
          _initializing = false;
          _initError =
              'Could not start the camera. Check that DermaTrack has camera permission.';
        });
      }
    }
  }

  // ----- Stream frame → ML Kit -----

  Future<void> _onCameraImage(CameraImage image) async {
    if (_capturing) return;
    if (_processingFrame) return;
    final now = DateTime.now();
    if (now.difference(_lastProcessed) < _minFrameInterval) return;
    _processingFrame = true;
    _lastProcessed = now;

    try {
      final input = _inputImageFromCameraImage(image);
      if (input == null) return;

      final face =
          await FaceDetectionService.instance.detectFromInputImage(input);

      // ML Kit reports landmarks/bbox in the rotated frame space — same
      // coordinate space we should pass to the evaluator. We use the
      // *rotated* dimensions (after rotation compensation) so the
      // evaluator's left/right reasoning matches what the patient sees.
      final isRotated90 = image.width != image.height &&
          // Heuristic: when the stream frame is wider than tall (landscape
          // sensor), portrait rotation effectively swaps dimensions for
          // ML Kit's reported coordinates.
          (image.height > image.width ? false : true);
      final fW = isRotated90 ? image.height : image.width;
      final fH = isRotated90 ? image.width : image.height;

      final result = RegionAlignmentEvaluator.instance.evaluate(
        region: _currentRegion,
        face: face,
        frameWidth: fW,
        frameHeight: fH,
      );

      if (!mounted) return;
      setState(() {
        _latestFace = face;
        _frameW = fW;
        _frameH = fH;
        _alignment = result;
      });
    } catch (e) {
      // Stream errors happen occasionally on lifecycle transitions. Log
      // and move on — next frame will retry.
      debugPrint('ScanSessionScreen._onCameraImage: $e');
    } finally {
      _processingFrame = false;
    }
  }

  /// Converts a [CameraImage] from the camera plugin to an [InputImage]
  /// ML Kit can process. Per the google_mlkit_face_detection package's
  /// canonical example — rotation compensation differs Android vs iOS.
  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final camera = _activeCamera;
    final controller = _controller;
    if (camera == null || controller == null) return null;

    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;

    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation =
          _orientations[controller.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation =
            (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  // ----- Capture -----

  Future<void> _captureCurrentRegion() async {
    if (_capturing) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    setState(() => _capturing = true);

    try {
      // Stop the stream before takePicture — the camera plugin can't do
      // both at once on some devices and will throw.
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }

      final XFile file = await controller.takePicture();
      final bytes = await file.readAsBytes();

      // Build the face_bbox payload from the most recent live detection.
      // It's slightly stale (one frame behind) but ML Kit's bbox of the
      // about-to-capture face is within tens of pixels of the actual
      // captured face — easily within the 15% padding the Edge Function
      // applies before filtering.
      Map<String, dynamic>? faceBbox;
      final face = _latestFace;
      final fW = _frameW;
      final fH = _frameH;
      if (face != null && fW != null && fH != null) {
        faceBbox = {
          'x': face.boundingBox.left,
          'y': face.boundingBox.top,
          'w': face.boundingBox.width,
          'h': face.boundingBox.height,
          'image_w': fW,
          'image_h': fH,
        };
      }

      final scan = await ScanService.instance.submitScan(
        bytes,
        region: _currentRegion,
        sessionId: _sessionId,
        faceBbox: faceBbox,
      );
      _capturedScans.add(scan);

      if (!mounted) return;

      if (_stepIndex >= _sessionOrder.length - 1) {
        // Session complete.
        await _stopAndDisposeCamera();
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                ScanSessionCompleteScreen(scans: List.of(_capturedScans)),
          ),
        );
        return;
      }

      // Advance to next region.
      setState(() {
        _stepIndex++;
        _capturing = false;
        _alignmentOverride = false;
        _alignment = const RegionAlignmentResult(
          aligned: false,
          noFace: true,
          score: 0,
          hint: 'Position your face in the frame.',
        );
      });

      // Restart the stream for the next region.
      if (mounted && _controller != null && !_controller!.value.isStreamingImages) {
        await _controller!.startImageStream(_onCameraImage);
      }
    } catch (e) {
      debugPrint('ScanSessionScreen._captureCurrentRegion failed: $e');
      if (!mounted) return;
      setState(() => _capturing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't capture: ${_friendlyError(e)}")),
      );
      // Try to restart the stream so the patient can retry.
      try {
        if (_controller != null && !_controller!.value.isStreamingImages) {
          await _controller!.startImageStream(_onCameraImage);
        }
      } catch (_) {/* fine — next frame will retry */}
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.startsWith('Exception: ')) return s.substring(11);
    return s;
  }

  Future<void> _abortConfirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop the session?'),
        content: Text(
          _capturedScans.isEmpty
              ? 'No regions have been captured yet — you can come back later.'
              : 'You\'ve captured ${_capturedScans.length} of ${_sessionOrder.length} regions. '
                  'The captured ones will be saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep scanning'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Stop session'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _stopAndDisposeCamera();
      if (!mounted) return;
      if (_capturedScans.isEmpty) {
        Navigator.of(context).pop();
      } else {
        // Even on abort, show the completion screen with what we got —
        // honest data, and the patient can review what landed.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                ScanSessionCompleteScreen(scans: List.of(_capturedScans)),
          ),
        );
      }
    }
  }

  // ----- Build -----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          tooltip: 'Stop session',
          onPressed: _abortConfirm,
        ),
        title: Text(
          'Step ${_stepIndex + 1} of ${_sessionOrder.length}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_initializing) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_initError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: Colors.white70, size: 56),
              const SizedBox(height: 16),
              Text(
                _initError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _initializeCamera,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1) Live camera preview, scaled to fill.
        Positioned.fill(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: CameraPreview(controller),
          ),
        ),
        // 2) Region overlay (oval template + corner brackets + label chip).
        Positioned.fill(
          child: CustomPaint(
            painter: RegionOverlayPainter(
              region: _currentRegion,
              aligned: _alignment.aligned,
              score: _alignment.score,
              noFace: _alignment.noFace,
            ),
          ),
        ),
        // 3) Progress bar across the top, below the app bar.
        Positioned(
          top: MediaQuery.of(context).padding.top + kToolbarHeight,
          left: 16,
          right: 16,
          child: _SessionProgressBar(
            stepIndex: _stepIndex,
            total: _sessionOrder.length,
          ),
        ),
        // 4) Hint + capture controls pinned to the bottom.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: _BottomControls(
              hint: _alignment.hint,
              aligned: _alignment.aligned,
              capturing: _capturing,
              overrideActive: _alignmentOverride,
              onCapture: _captureEnabled ? _captureCurrentRegion : null,
              onOverride: () {
                if (mounted) {
                  setState(() => _alignmentOverride = true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Alignment check skipped — capture button enabled. '
                          'Use only when ML Kit is misfiring.'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              },
              regionLabel: _currentRegion.label,
            ),
          ),
        ),
      ],
    );
  }
}

/// Five-segment progress indicator pinned just below the app bar.
class _SessionProgressBar extends StatelessWidget {
  const _SessionProgressBar({required this.stepIndex, required this.total});
  final int stepIndex;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i <= stepIndex
                    ? AppTheme.primary
                    : Colors.white.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (i < total - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

/// Bottom strip with the hint text and the capture button. Long-press the
/// capture button when disabled to invoke the alignment override.
class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.hint,
    required this.aligned,
    required this.capturing,
    required this.overrideActive,
    required this.onCapture,
    required this.onOverride,
    required this.regionLabel,
  });

  final String hint;
  final bool aligned;
  final bool capturing;
  final bool overrideActive;
  final VoidCallback? onCapture;
  final VoidCallback onOverride;
  final String regionLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Region name + hint
          Text(
            regionLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: aligned
                  ? AppTheme.primary
                  : Colors.white.withValues(alpha: 0.9),
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 16),
          // Capture button
          GestureDetector(
            onLongPress: onCapture == null && !capturing ? onOverride : null,
            child: SizedBox(
              width: 76,
              height: 76,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer ring
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: aligned || overrideActive
                            ? AppTheme.primary
                            : Colors.white.withValues(alpha: 0.6),
                        width: 4,
                      ),
                    ),
                  ),
                  // Inner button
                  Material(
                    color: capturing
                        ? AppTheme.primary.withValues(alpha: 0.6)
                        : (onCapture == null
                            ? Colors.white.withValues(alpha: 0.25)
                            : AppTheme.primary),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onCapture,
                      child: SizedBox(
                        width: 60,
                        height: 60,
                        child: capturing
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Icon(
                                Icons.camera_alt_rounded,
                                color: onCapture == null
                                    ? Colors.white.withValues(alpha: 0.5)
                                    : Colors.white,
                                size: 28,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Skip-override hint, shown when disabled.
          if (onCapture == null && !capturing)
            Text(
              overrideActive
                  ? 'Override active — tap to capture'
                  : 'Long-press to skip alignment check',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}
