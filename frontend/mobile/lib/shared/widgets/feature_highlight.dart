import 'package:flutter/material.dart';

/// Feature highlight item for welcome screen.
class FeatureHighlight extends StatelessWidget {
  const FeatureHighlight({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.accentColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = accentColor ?? scheme.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A row of feature highlights for the welcome screen.
class FeatureHighlightsSection extends StatelessWidget {
  const FeatureHighlightsSection({
    super.key,
    required this.isArabic,
  });

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final features = isArabic
        ? [
            (
              Icons.fitness_center_rounded,
              'نوادٍ متعددة',
              'اكتشف أفضل النوادي',
              scheme.primary
            ),
            (
              Icons.person_rounded,
              'مدربين محترفين',
              'اختر مدربك الخاص',
              scheme.secondary
            ),
            (
              Icons.shopping_bag_rounded,
              'منتجات رياضية',
              'تسوق من المتجر',
              scheme.tertiary
            ),
          ]
        : [
            (
              Icons.fitness_center_rounded,
              'Multiple Gyms',
              'Discover top gyms',
              scheme.primary
            ),
            (
              Icons.person_rounded,
              'Pro Trainers',
              'Hire your trainer',
              scheme.secondary
            ),
            (
              Icons.shopping_bag_rounded,
              'Fitness Store',
              'Shop products',
              scheme.tertiary
            ),
          ];

    return Column(
      children: features.map((f) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FeatureHighlight(
            icon: f.$1,
            title: f.$2,
            subtitle: f.$3,
            accentColor: f.$4,
          ),
        );
      }).toList(),
    );
  }
}
