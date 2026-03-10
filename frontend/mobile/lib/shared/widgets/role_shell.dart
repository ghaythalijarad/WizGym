import 'dart:ui';

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
        // Admin uses the web dashboard — fallback to user view in mobile
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
            NavigationDestination(icon: Icon(Icons.fitness_center_outlined), label: 'خططي'),
            NavigationDestination(icon: Icon(Icons.person_outline), label: 'الملف'),
          ],
        );
      case AppRole.owner:
        return _RoleTabsConfig(
          pages: [
            OwnerHomePage(session: session),
            OwnerStudioPage(session: session),
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
            NavigationDestination(icon: Icon(Icons.person_outline), label: 'الملف'),
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


