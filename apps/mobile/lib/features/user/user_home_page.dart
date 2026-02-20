import 'package:flutter/material.dart';

import '../../shared/widgets/metric_card.dart';

class UserHomePage extends StatelessWidget {
  const UserHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        MetricCard(title: 'تمارين هذا الأسبوع', value: '4 / 5', icon: Icons.check_circle_outline),
        MetricCard(title: 'السعرات المحروقة', value: '2,980', icon: Icons.local_fire_department_outlined),
        MetricCard(title: 'سلسلة الإنجاز', value: '12 يوم', icon: Icons.emoji_events_outlined),
      ],
    );
  }
}
