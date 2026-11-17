import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Small drawn stand-in for the Lidl roundel (yellow core, blue ring).
/// Used in the app bar and on card faces.
class LidlBadge extends StatelessWidget {
  const LidlBadge({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.yellow,
        border: Border.all(color: AppColors.blue, width: size * 0.10),
      ),
      alignment: Alignment.center,
      child: Text(
        'Lidl',
        style: TextStyle(
          fontFamily: 'Space Grotesk',
          fontWeight: FontWeight.w700,
          fontSize: size * 0.32,
          fontStyle: FontStyle.italic,
          color: AppColors.blue,
          height: 1.0,
        ),
      ),
    );
  }
}
