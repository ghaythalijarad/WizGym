import 'package:flutter/material.dart';

import '../../shared/widgets/metric_card.dart';

class OwnerHomePage extends StatelessWidget {
  const OwnerHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        MetricCard(title: 'الاشتراكات النشطة', value: '1,248', icon: Icons.groups_outlined),
        MetricCard(title: 'إيراد اليوم', value: '12,400 ر.س', icon: Icons.payments_outlined),
        MetricCard(title: 'نسبة الحضور', value: '82%', icon: Icons.query_stats_outlined),
      ],
    );
  }
}
