import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/app_role.dart';
import '../../features/admin/admin_home_page.dart';
import '../../features/admin/gym_approval_page.dart';
import '../../features/admin/subscription_management_page.dart';
import '../../features/marketplace/owner_studio_page.dart';
import '../../features/marketplace/trainer_gyms_page.dart';
import '../../features/marketplace/user_marketplace_page.dart';
import '../../features/owner/owner_home_page.dart';
import '../../features/owner/owner_members_page.dart';
import '../../features/owner/owner_plans_page.dart';
import '../../features/trainer/trainer_home_page.dart';
import '../../features/trainer/trainer_plans_page.dart';
import '../../features/trainer/trainer_subscriptions_page.dart';
import '../../features/user/user_home_page.dart';
import '../../features/plans/user_plans_page.dart';
import '../../features/profile/role_profile_page.dart';
import 'app_background.dart';

class RoleShell extends StatefulWidget {
  const RoleShell({super.key, required this.role, this.onLogout, this.session});

  final AppRole role;
  final VoidCallback? onLogout;
  final AuthSession? session;

  @override
  State<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends State<RoleShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final config = _tabsForRole(widget.role, widget.session);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('GymOS - ${widget.role.labelAr}')),
      extendBody: true,
      body: AppBackground(child: config.pages[_index]),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.86),
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(22),
              ),
              child: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (value) => setState(() => _index = value),
                destinations: config.destinations,
              ),
            ),
          ),
        ),
      ),
    );
  }

  _RoleTabsConfig _tabsForRole(AppRole role, AuthSession? session) {
    switch (role) {
      case AppRole.admin:
        return const _RoleTabsConfig(
          pages: [
            AdminHomePage(),
            GymApprovalPage(),
            SubscriptionManagementPage(),
            _SimpleListPage(title: 'التدقيق', items: ['سجل القرارات', 'سجل التغييرات', 'تقارير المخاطر']),
          ],
          destinations: [
            NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), label: 'لوحة المدير'),
            NavigationDestination(icon: Icon(Icons.verified_user_outlined), label: 'اعتماد النوادي'),
            NavigationDestination(icon: Icon(Icons.manage_accounts_outlined), label: 'الاشتراكات'),
            NavigationDestination(icon: Icon(Icons.fact_check_outlined), label: 'التدقيق'),
          ],
        );
      case AppRole.owner:
        return _RoleTabsConfig(
          pages: [
            OwnerHomePage(session: session),
            const OwnerStudioPage(),
            OwnerMembersPage(session: session),
            OwnerPlansPage(session: session),
            RoleProfilePage(role: role, session: session),
          ],
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'الرئيسية'),
            NavigationDestination(icon: Icon(Icons.storefront_outlined), label: 'الاستوديو'),
            NavigationDestination(
                icon: Icon(Icons.group_outlined), label: 'الأعضاء'),
            NavigationDestination(
                icon: Icon(Icons.card_membership_outlined), label: 'الخطط'),
            NavigationDestination(
                icon: Icon(Icons.person_outline), label: 'الملف'),
          ],
        );
      case AppRole.trainer:
        return _RoleTabsConfig(
          pages: [
            const TrainerHomePage(),
            const TrainerGymsPage(),
            const TrainerSubscriptionsPage(),
            const TrainerPlansPage(),
            RoleProfilePage(role: role, session: session),
          ],
          destinations: const [
            NavigationDestination(icon: Icon(Icons.today_outlined), label: 'اليوم'),
            NavigationDestination(icon: Icon(Icons.apartment_outlined), label: 'نواديي'),
            NavigationDestination(
                icon: Icon(Icons.group_outlined), label: 'المتدربون'),
            NavigationDestination(
                icon: Icon(Icons.fitness_center_outlined), label: 'الخطط'),
            NavigationDestination(
                icon: Icon(Icons.person_outline), label: 'الملف'),
          ],
        );
      case AppRole.user:
        return _RoleTabsConfig(
          pages: [
            const UserHomePage(),
            UserMarketplacePage(session: session),
            UserPlansPage(session: session),
            RoleProfilePage(role: role, session: session),
          ],
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined), label: 'الرئيسية'),
            NavigationDestination(
                icon: Icon(Icons.search_outlined), label: 'النوادي'),
            NavigationDestination(
                icon: Icon(Icons.fitness_center_outlined), label: 'خططي'),
            NavigationDestination(
                icon: Icon(Icons.person_outline), label: 'الملف'),
          ],
        );
      case AppRole.trainee:
        return _RoleTabsConfig(
          pages: [
            const UserHomePage(),
            UserMarketplacePage(session: session),
            UserPlansPage(session: session),
            RoleProfilePage(role: role, session: session),
          ],
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), label: 'الرئيسية'),
            NavigationDestination(icon: Icon(Icons.search_outlined), label: 'النوادي'),
            NavigationDestination(
                icon: Icon(Icons.fitness_center_outlined), label: 'خططي'),
            NavigationDestination(icon: Icon(Icons.person_outline), label: 'الملف'),
          ],
        );
    }
  }
}

class _RoleTabsConfig {
  const _RoleTabsConfig({required this.pages, required this.destinations});

  final List<Widget> pages;
  final List<NavigationDestination> destinations;
}

class _SimpleListPage extends StatelessWidget {
  const _SimpleListPage({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 14),
        ...items.map(
          (item) => Card(
            child: ListTile(
              title: Text(item),
              trailing: const Icon(Icons.chevron_left),
            ),
          ),
        ),
      ],
    );
  }
}
