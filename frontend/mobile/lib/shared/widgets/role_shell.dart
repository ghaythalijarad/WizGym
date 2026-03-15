import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/app_role.dart';
import '../../features/marketplace/owner_studio_page.dart';
import '../../features/marketplace/trainer_gyms_page.dart';
import '../../features/marketplace/user_marketplace_page.dart';
import '../../features/owner/owner_home_page.dart';
import '../../features/owner/owner_members_page.dart';
import '../../features/owner/owner_plans_page.dart';
import '../../features/plans/user_plans_page.dart';
import '../../features/profile/role_profile_page.dart';
import '../../features/trainer/trainer_home_page.dart';
import '../../features/trainer/trainer_plans_page.dart';
import '../../features/trainer/trainer_subscriptions_page.dart';
import '../../features/user/user_home_page.dart';
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

  void _goToTab(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final config = _tabsForRole(widget.role, widget.session);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: null,
      // extendBody removed — nav bar is fixed, content never goes behind it
      body: SafeArea(
        bottom: true,
        child: AppBackground(child: config.pages[_index]),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: scheme.surface,
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: config.destinations,
      ),
    );
  }

  _RoleTabsConfig _tabsForRole(AppRole role, AuthSession? session) {
    switch (role) {
      case AppRole.admin:
        // Admin uses the web dashboard — fallback to user view in mobile
        return _RoleTabsConfig(
          pages: [
            const Material(child: UserHomePage()),
            Material(child: UserMarketplacePage(session: session)),
            Material(child: UserPlansPage(session: session)),
            Material(child: RoleProfilePage(role: role, session: session)),
          ],
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), label: 'الرئيسية'),
            NavigationDestination(icon: Icon(Icons.search_outlined), label: 'النوادي'),
            NavigationDestination(icon: Icon(Icons.fitness_center_outlined), label: 'خططي'),
            NavigationDestination(icon: Icon(Icons.person_outline), label: 'الملف'),
          ],
        );
      case AppRole.owner:
        return _RoleTabsConfig(
          pages: [
            Material(child: OwnerHomePage(session: session)),
            Material(child: OwnerStudioPage(session: session)),
            Material(child: OwnerMembersPage(session: session)),
            Material(child: OwnerPlansPage(session: session)),
            Material(child: RoleProfilePage(role: role, session: session)),
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
            TrainerHomePage(session: session),
            TrainerGymsPage(session: session),
            TrainerSubscriptionsPage(session: session),
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
            Material(child: UserHomePage(onGoToTab: _goToTab)),
            Material(child: UserMarketplacePage(session: session)),
            Material(child: UserPlansPage(session: session)),
            Material(child: RoleProfilePage(role: role, session: session)),
          ],
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined), label: 'الرئيسية'),
            NavigationDestination(
                icon: Icon(Icons.search_outlined), label: 'النوادي'),
            NavigationDestination(
                icon: Icon(Icons.fitness_center_outlined), label: 'خططي'),
            NavigationDestination(icon: Icon(Icons.person_outline), label: 'الملف'),
          ],
        );
      case AppRole.trainee:
        return _RoleTabsConfig(
          pages: [
            Material(child: UserHomePage(onGoToTab: _goToTab)),
            Material(child: UserMarketplacePage(session: session)),
            Material(child: UserPlansPage(session: session)),
            Material(child: RoleProfilePage(role: role, session: session)),
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


