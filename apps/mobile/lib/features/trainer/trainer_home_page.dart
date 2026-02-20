import 'package:flutter/material.dart';

import '../../shared/widgets/metric_card.dart';

class TrainerHomePage extends StatelessWidget {
  const TrainerHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        MetricCard(title: 'جلسات اليوم', value: '8', icon: Icons.event_note_outlined),
        MetricCard(title: 'عملاء نشطون', value: '32', icon: Icons.people_alt_outlined),
        MetricCard(title: 'معدل الالتزام', value: '89%', icon: Icons.trending_up_outlined),
      ],
    );
  }
}
