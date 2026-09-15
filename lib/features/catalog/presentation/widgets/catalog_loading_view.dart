import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Full-screen loading state shown while a source's *first* catalog sync is
/// running — i.e. when there is nothing cached to display yet.
///
/// A refresh of an already-populated catalog deliberately does NOT use this:
/// that runs in the background while the cached catalog stays browsable, and
/// is surfaced by the app shell's sync indicator instead.
class CatalogLoadingView extends StatelessWidget {
  /// Live step text from the sync (e.g. "Downloading Movies..."). Falls back
  /// to a generic line when the sync has not reported a step yet.
  final String progress;

  /// What is being loaded, used in the headline: "Movies", "TV Shows".
  final String label;

  const CatalogLoadingView({
    super.key,
    required this.progress,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final step = progress.trim().isNotEmpty
        ? progress.trim()
        : 'Contacting your provider...';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Building your $label library',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              step,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: AppColors.textLight),
            ),
            const SizedBox(height: 18),
            const Text(
              'Catalogs can hold tens of thousands of titles, so the first '
              'sync takes a minute. It is cached afterwards, so this only '
              'happens once.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
