import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.onTap,
    this.accent,
  });

  final String title;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  /// Optional override colour for the icon + value. Defaults to [AppTheme.gold].
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final effectiveAccent = accent ?? AppTheme.gold;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: effectiveAccent.withValues(alpha: 0.18),
              ),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  effectiveAccent.withValues(alpha: 0.06),
                  Colors.transparent,
                ],
              ),
            ),
            child: Row(
              children: [
                // ── Left: large value + label ──────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        value,
                        style: tt.displaySmall?.copyWith(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: effectiveAccent,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        title,
                        style: tt.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // ── Right: icon container ──────────────────────────────────
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: effectiveAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: effectiveAccent.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Icon(icon, color: effectiveAccent, size: 22),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
