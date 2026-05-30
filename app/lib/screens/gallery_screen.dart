import 'package:flutter/material.dart';

import '../services/scan_service.dart';
import '../theme/app_theme.dart';
import '../widgets/scan_thumbnail.dart';
import 'scan_detail_screen.dart';

/// Full-screen grid of every scan the user has taken, reached via the
/// "View all" link on the profile preview row.
///
/// Listens to [ScanService] so the grid refreshes when a new scan is
/// submitted from the camera screen (without the user having to back out
/// and re-enter this screen).
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  @override
  void initState() {
    super.initState();
    ScanService.instance.addListener(_onScansChanged);
  }

  @override
  void dispose() {
    ScanService.instance.removeListener(_onScansChanged);
    super.dispose();
  }

  void _onScansChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scans = ScanService.instance.scans;
    final isLoading = ScanService.instance.isLoading;

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(title: const Text('All scans')),
      body: scans.isEmpty
          ? (isLoading
              ? const Center(child: CircularProgressIndicator())
              : const _EmptyState())
          : Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 16,
                  // 0.75 gives ~10px headroom for the date label below the
                  // square image; earlier 0.82 was 2-3px too tight on phones
                  // where the system font scales slightly larger.
                  childAspectRatio: 0.75,
                ),
                itemCount: scans.length,
                itemBuilder: (context, index) {
                  final scan = scans[index];
                  return ScanThumbnail(
                    scan: scan,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ScanDetailScreen(scan: scan),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.photo_library_outlined,
                color: AppTheme.primary,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No scans yet',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'Take your first scan to start building your history.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
