// filepath: /Users/ghaythallaheebi/WizGymProd/apps/mobile/lib/shared/widgets/animated_logo.dart
import 'package:flutter/material.dart';

/// Animated WizGym logo with pulse and glow effect.
class AnimatedLogo extends StatefulWidget {
  const AnimatedLogo({
    super.key,
    this.size = 64,
    this.showText = true,
  });

  final double size;
  final bool showText;

  @override
  State<AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<AnimatedLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _glowAnim = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.scale(
              scale: _pulseAnim.value,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(widget.size * 0.25),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: _glowAnim.value),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.fitness_center_rounded,
                  color: scheme.onPrimary,
                  size: widget.size * 0.5,
                ),
              ),
            ),
            if (widget.showText) ...[
              const SizedBox(height: 12),
              Text(
                'WizGym',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
              ),
            ],
          ],
        );
      },
    );
  }
}
