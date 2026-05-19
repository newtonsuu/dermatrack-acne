import 'package:flutter/material.dart';

import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/scan_thumbnail.dart';

/// Full-screen grid of every scan the user has taken, reached via the
/// "View all" link on the profile preview row.
class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scans = ProfileService.instance.scans;

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(title: const Text('All scans')),
      body: scans.isEmpty
          ? const _EmptyState()
          : Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.82,
                ),
                itemCount: scans.length,
                itemBuilder: (context, index) {
                  final scan = scans[index];
                  return ScanThumbnail(
                    scan: scan,
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Scan detail for ${scan.id} — coming soon.',
                        ),
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
