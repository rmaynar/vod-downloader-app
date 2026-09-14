import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class FallbackPoster extends StatelessWidget {
  final double? width;
  final double? height;

  const FallbackPoster({super.key, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF14141F),
            Color(0xFF0A0A0F),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceElevated,
                border: Border.all(color: AppColors.borderLight, width: 1.5),
              ),
              child: const Center(
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: AppColors.primary,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'VODCATALOG',
              style: TextStyle(
                color: AppColors.textLight,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'No Poster Available',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
