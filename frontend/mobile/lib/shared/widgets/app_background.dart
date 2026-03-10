import 'dart:ui';

import 'package:flutter/material.dart';

/// A reusable backdrop for "modern" screens: soft gradient + blurred blobs.
/// Kept intentionally subtle so content remains readable in Arabic RTL layouts.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  scheme.surface,
                  scheme.surfaceContainerHighest.withValues(alpha: 0.85),
                  scheme.surface,
                ],
              ),
            ),
          ),
        ),
        const _Blob(offset: Offset(0.85, 0.10)),
        const _Blob(offset: Offset(0.10, 0.30), colorHint: _BlobColorHint.accent),
        const _Blob(offset: Offset(0.25, 0.95), colorHint: _BlobColorHint.warm),
        Positioned.fill(child: child),
      ],
    );
  }
}

enum _BlobColorHint { accent, warm, cool }

class _Blob extends StatelessWidget {
  const _Blob({
    required this.offset,
    this.colorHint = _BlobColorHint.cool,
  });

  final Offset offset;
  final _BlobColorHint colorHint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Color base;
    switch (colorHint) {
      case _BlobColorHint.accent:
        base = scheme.primary;
        break;
      case _BlobColorHint.warm:
        base = scheme.tertiary;
        break;
      case _BlobColorHint.cool:
        base = scheme.secondary;
        break;
    }

    return Positioned.fill(
      child: FractionallySizedBox(
        alignment: Alignment(offset.dx * 2 - 1, offset.dy * 2 - 1),
        widthFactor: 0.9,
        heightFactor: 0.55,
        child: IgnorePointer(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      base.withValues(alpha: 0.22),
                      base.withValues(alpha: 0.00),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

