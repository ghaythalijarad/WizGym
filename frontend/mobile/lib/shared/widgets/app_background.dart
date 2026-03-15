import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Premium dark backdrop: near-black canvas with very subtle brand-color glows.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Deep dark canvas
        const Positioned.fill(
          child: ColoredBox(color: Color(0xFF0F0F1C)),
        ),
        // Faint gold glow — top-right
        Positioned(
          top: -80,
          right: -60,
          width: 260,
          height: 260,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.gold.withValues(alpha: 0.18),
                    AppTheme.gold.withValues(alpha: 0.00),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Faint gold glow — bottom-left
        Positioned(
          bottom: -60,
          left: -40,
          width: 200,
          height: 200,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.gold.withValues(alpha: 0.12),
                    AppTheme.gold.withValues(alpha: 0.00),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

