import 'package:flutter/material.dart';

import '../../core/models/app_role.dart';
import '../../shared/widgets/app_background.dart';
import '../../shared/widgets/role_shell.dart';

class RoleSelectorPage extends StatelessWidget {
  const RoleSelectorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: AppBackground(
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WizGym',
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              color: scheme.onSurface,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'منصة حديثة للنوادي والمدربين والمشتركين',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.80),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'اختر دورك للبدء',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Icon(Icons.arrow_back_ios_new_rounded, color: scheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                sliver: SliverGrid(
                  delegate: SliverChildListDelegate(
                    [
                      _RoleCard(
                        title: AppRole.user.labelAr,
                        subtitle: 'استكشف النوادي، انضم، وظّف مدربك',
                        icon: Icons.person_outline_rounded,
                        accent: scheme.primary,
                        onTap: () => _open(context, AppRole.user),
                      ),
                      _RoleCard(
                        title: AppRole.trainer.labelAr,
                        subtitle: 'انضم حتى 4 نوادٍ وتابع عملاءك',
                        icon: Icons.fitness_center_rounded,
                        accent: scheme.secondary,
                        onTap: () => _open(context, AppRole.trainer),
                      ),
                      _RoleCard(
                        title: AppRole.owner.labelAr,
                        subtitle: 'أضف مرافق ومنتجات وحدد خدمات النادي',
                        icon: Icons.storefront_outlined,
                        accent: scheme.tertiary,
                        onTap: () => _open(context, AppRole.owner),
                      ),
                      _RoleCard(
                        title: AppRole.admin.labelAr,
                        subtitle: 'اعتماد النوادي وإدارة الاشتراكات',
                        icon: Icons.verified_user_outlined,
                        accent: scheme.onSurface,
                        onTap: () => _open(context, AppRole.admin),
                      ),
                    ],
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.92,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, AppRole role) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoleShell(role: role),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              scheme.surface.withValues(alpha: 0.92),
              accent.withValues(alpha: 0.08),
            ],
          ),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.08),
              blurRadius: 30,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Align(
                alignment: Alignment.bottomLeft,
                child: Icon(Icons.arrow_back_rounded, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
