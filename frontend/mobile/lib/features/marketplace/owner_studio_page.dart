import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';
import '../owner/owner_create_gym_page.dart';
import 'marketplace_api_service.dart';
import 'marketplace_models.dart';
import 'owner_gym_photos_section.dart';
import 'owner_gym_subscription_request_section.dart';

class OwnerStudioPage extends StatefulWidget {
  const OwnerStudioPage({super.key, this.session});

  final AuthSession? session;

  @override
  State<OwnerStudioPage> createState() => _OwnerStudioPageState();
}

class _OwnerStudioPageState extends State<OwnerStudioPage> {
  static const List<String> _audiences = ['MEN_ONLY', 'WOMEN_ONLY', 'MIXED'];
  static const List<String> _amenityPresets = [
    'Food Bar',
    'Sauna',
    'Steam Room',
    'Pool',
    'Parking',
    'Kids Area',
    'Ice Bath',
    'Massage Room',
  ];

  static const Map<String, String> _amenityAr = {
    'Food Bar': 'بار غذائي',
    'Sauna': 'ساونا',
    'Steam Room': 'غرفة بخار',
    'Pool': 'مسبح',
    'Parking': 'موقف سيارات',
    'Kids Area': 'منطقة أطفال',
    'Ice Bath': 'حمام ثلج',
    'Massage Room': 'غرفة مساج',
  };

  String _amenityLabel(BuildContext context, String key) {
    final lang = Localizations.localeOf(context).languageCode.toLowerCase();
    if (lang.startsWith('ar')) return _amenityAr[key] ?? key;
    return key;
  }

  late final MarketplaceApiService _api;
  late Future<List<GymSummary>> _gymsFuture;
  String? _selectedGymId;
  String? _assetsGymId;
  String? _profileGymId;
  String _selectedAudience = 'MIXED';
  Set<String> _selectedAmenities = <String>{};
  Map<String, DayHours> _openingHours = {};

  // ── expand state ──────────────────────────────────────────────
  bool _facilityExpanded = false;
  bool _productExpanded = false;

  final TextEditingController _facilityNameController = TextEditingController();
  final TextEditingController _facilityDescriptionController =
      TextEditingController();
  final TextEditingController _productTitleController = TextEditingController();
  final TextEditingController _productDescriptionController =
      TextEditingController();
  final TextEditingController _productPriceController = TextEditingController();

  late Future<_StudioAssets> _assetsFuture;

  void _clearComposers() {
    _facilityNameController.clear();
    _facilityDescriptionController.clear();
    _productTitleController.clear();
    _productDescriptionController.clear();
    _productPriceController.clear();
    _facilityExpanded = false;
    _productExpanded = false;
  }

  @override
  void initState() {
    super.initState();
    _api = MarketplaceApiService(role: AppRole.owner, session: widget.session);
    _gymsFuture = _api.fetchOwnerGyms();
    _assetsFuture =
        Future.value(const _StudioAssets(facilities: [], products: []));

    // If navigated here from OwnerHomePage, a gymId may be provided via route arguments.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String && args.isNotEmpty) {
        setState(() {
          _selectedGymId = args;
        });
      }
    });
  }

  @override
  void dispose() {
    _facilityNameController.dispose();
    _facilityDescriptionController.dispose();
    _productTitleController.dispose();
    _productDescriptionController.dispose();
    _productPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: FutureBuilder<List<GymSummary>>(
        future: _gymsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorState(onRetry: _reloadGyms);
          }

          final gyms = snapshot.data ?? const <GymSummary>[];

          if (gyms.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('لا توجد نوادي مملوكة لك حالياً.'),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () async {
                    final created = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) =>
                            OwnerCreateGymPage(session: widget.session),
                      ),
                    );
                    if (created == true && mounted) {
                      setState(() {
                        _gymsFuture = _api.fetchOwnerGyms();
                      });
                    }
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('إنشاء نادي'),
                ),
              ],
            );
          }

          _selectedGymId ??= gyms.first.id;
          final selectedGym = gyms.firstWhere(
            (item) => item.id == _selectedGymId,
            orElse: () => gyms.first,
          );

          if (_selectedGymId != _profileGymId) {
            _profileGymId = _selectedGymId;
            _selectedAudience = selectedGym.audience;
            _selectedAmenities = selectedGym.amenities.toSet();
            _openingHours = Map<String, DayHours>.from(
                selectedGym.openingHours ?? {});
          }

          if (_selectedGymId != _assetsGymId) {
            _assetsGymId = _selectedGymId;
            _assetsFuture = _loadAssets(_selectedGymId!);
          }

          return RefreshIndicator(
            onRefresh: _refreshAll,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _selectedGymId,
                  decoration: const InputDecoration(labelText: 'اختر النادي'),
                  items: gyms
                      .map(
                        (gym) => DropdownMenuItem<String>(
                          value: gym.id,
                          child: Text('${gym.name} (${gym.city})'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }

                    setState(() {
                      _selectedGymId = value;
                      _assetsGymId = value;
                      _assetsFuture = _loadAssets(value);
                      final gym = gyms.firstWhere(
                        (item) => item.id == value,
                        orElse: () => gyms.first,
                      );
                      _profileGymId = value;
                      _selectedAudience = gym.audience;
                      _selectedAmenities = gym.amenities.toSet();
                      _openingHours = Map<String, DayHours>.from(
                          gym.openingHours ?? {});

                      // Avoid showing stale form inputs from the previously selected gym.
                      _clearComposers();
                    });
                  },
                ),
                const SizedBox(height: 16),
                _buildGymProfileSettings(),
                const SizedBox(height: 14),
                if (_selectedGymId != null) ...[
                  OwnerGymSubscriptionRequestSection(
                    key: ValueKey('sub-requests-${_selectedGymId!}'),
                    gymId: _selectedGymId!,
                    api: _api,
                  ),
                  const SizedBox(height: 14),
                  OwnerGymPhotosSection(
                    key: ValueKey('gym-photos-${_selectedGymId!}'),
                    gymId: _selectedGymId!,
                    api: _api,
                  ),
                  const SizedBox(height: 14),
                ],
                _buildFacilityComposer(),
                const SizedBox(height: 10),
                _buildProductComposer(),
                const SizedBox(height: 20),
                FutureBuilder<_StudioAssets>(
                  key: ValueKey('assets-${_selectedGymId ?? 'none'}'),
                  future: _assetsFuture,
                  builder: (context, assetsSnapshot) {
                    if (assetsSnapshot.connectionState !=
                        ConnectionState.done) {
                      return const Center(
                          child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ));
                    }

                    if (assetsSnapshot.hasError) {
                      return Card(
                        child: ListTile(
                          title: const Text('تعذر تحميل المرافق والمنتجات'),
                          trailing: TextButton(
                              onPressed: _reloadAssets,
                              child: const Text('إعادة')),
                        ),
                      );
                    }

                    final assets = assetsSnapshot.data ??
                        const _StudioAssets(facilities: [], products: []);

                    return _AssetsDisplay(
                      assets: assets,
                      context: context,
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Amenity icon map ──────────────────────────────────────────
  static const Map<String, IconData> _amenityIcons = {
    'Food Bar': Icons.restaurant_outlined,
    'Sauna': Icons.whatshot_outlined,
    'Steam Room': Icons.hot_tub_outlined,
    'Pool': Icons.pool_outlined,
    'Parking': Icons.local_parking_outlined,
    'Kids Area': Icons.child_care_outlined,
    'Ice Bath': Icons.ac_unit_outlined,
    'Massage Room': Icons.spa_outlined,
  };

  Widget _buildGymProfileSettings() {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.18)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.gold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.tune_rounded,
                    color: AppTheme.gold, size: 18),
              ),
              const SizedBox(width: 10),
              Text('إعدادات النادي',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: AppTheme.gold)),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _selectedAudience,
            decoration: const InputDecoration(labelText: 'فئة النادي'),
            items: _audiences
                .map((item) => DropdownMenuItem<String>(
                      value: item,
                      child: Text(_audienceLabel(item)),
                    ))
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedAudience = value);
            },
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Icon(Icons.star_outline_rounded,
                  size: 16, color: AppTheme.gold),
              const SizedBox(width: 6),
              Text('الخدمات المتوفرة',
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: AppTheme.textSecondary, letterSpacing: 0.4)),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.82,
            children: _amenityPresets.map((item) {
              final selected = _selectedAmenities.contains(item);
              final icon = _amenityIcons[item] ?? Icons.check_circle_outline;
              final label = _amenityLabel(context, item);
              return _AmenityTile(
                label: label,
                icon: icon,
                selected: selected,
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    if (selected) {
                      _selectedAmenities.remove(item);
                    } else {
                      _selectedAmenities.add(item);
                    }
                  });
                },
              );
            }).toList(growable: false),
          ),
          const SizedBox(height: 22),

          // ── Opening hours ─────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.schedule_rounded,
                  size: 16, color: AppTheme.gold),
              const SizedBox(width: 6),
              Text('أوقات الدوام',
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: AppTheme.textSecondary, letterSpacing: 0.4)),
            ],
          ),
          const SizedBox(height: 10),
          ...kWeekDayKeys.map((day) {
            final label = kWeekDayLabelsAr[day] ?? day;
            final hours = _openingHours[day];
            final enabled = hours != null;
            return _DayHoursRow(
              dayLabel: label,
              enabled: enabled,
              open: hours?.open ?? '',
              close: hours?.close ?? '',
              onToggle: (val) {
                setState(() {
                  if (val) {
                    _openingHours[day] =
                        const DayHours(open: '06:00', close: '22:00');
                  } else {
                    _openingHours.remove(day);
                  }
                });
              },
              onOpenChanged: (val) {
                setState(() {
                  _openingHours[day] = DayHours(
                      open: val, close: hours?.close ?? '22:00');
                });
              },
              onCloseChanged: (val) {
                setState(() {
                  _openingHours[day] = DayHours(
                      open: hours?.open ?? '06:00', close: val);
                });
              },
            );
          }),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveGymProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gold,
                foregroundColor: AppTheme.textOnGold,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
              child: const Text('حفظ إعدادات النادي',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Expandable facility composer ─────────────────────────────
  Widget _buildFacilityComposer() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: _facilityExpanded
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surface,
        border: Border.all(
          color: _facilityExpanded ? scheme.primary : scheme.outline,
          width: _facilityExpanded ? 1.5 : 1.0,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // ── Header row ────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _facilityExpanded = !_facilityExpanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _facilityExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(Icons.chevron_right,
                        size: 20, color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text('إضافة مرفق',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _facilityExpanded
                            ? scheme.primary
                            : scheme.onSurface,
                      )),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _facilityExpanded
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.construction_outlined,
                        size: 16,
                        color: _facilityExpanded
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          // ── Expanded body ────────────────────────────────────
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Divider(height: 1, color: scheme.outline),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _facilityNameController,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'اسم المرفق',
                      prefixIcon: Icon(Icons.label_outline, size: 18),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _facilityDescriptionController,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'وصف المرفق',
                      prefixIcon: Icon(Icons.notes_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _submitFacility,
                    icon: const Icon(Icons.send_outlined, size: 16),
                    label: const Text('نشر المرفق'),
                  ),
                ],
              ),
            ),
            crossFadeState: _facilityExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 260),
          ),
        ],
      ),
    );
  }

  // ── Expandable product composer ──────────────────────────────
  Widget _buildProductComposer() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: _productExpanded
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surface,
        border: Border.all(
          color: _productExpanded ? scheme.primary : scheme.outline,
          width: _productExpanded ? 1.5 : 1.0,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // ── Header row ────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _productExpanded = !_productExpanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _productExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(Icons.chevron_right,
                        size: 20, color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text('إضافة منتج / إعلان',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _productExpanded
                            ? scheme.primary
                            : scheme.onSurface,
                      )),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _productExpanded
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.storefront_outlined,
                        size: 16,
                        color: _productExpanded
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          // ── Expanded body ────────────────────────────────────
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Divider(height: 1, color: scheme.outline),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _productTitleController,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'عنوان المنتج',
                      prefixIcon: Icon(Icons.title_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _productDescriptionController,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'وصف المنتج',
                      prefixIcon: Icon(Icons.notes_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _productPriceController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'السعر (اختياري)',
                      prefixIcon: Icon(Icons.payments_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _submitProduct,
                    icon: const Icon(Icons.send_outlined, size: 16),
                    label: const Text('نشر المنتج'),
                  ),
                ],
              ),
            ),
            crossFadeState: _productExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 260),
          ),
        ],
      ),
    );
  }

  Future<void> _submitFacility() async {
    final gymId = _selectedGymId;
    final name = _facilityNameController.text.trim();

    if (gymId == null || name.isEmpty) {
      _showMessage('اختر النادي وأدخل اسم المرفق');
      return;
    }

    try {
      await _api.createFacility(
        gymId: gymId,
        name: name,
        description: _facilityDescriptionController.text,
      );
      _facilityNameController.clear();
      _facilityDescriptionController.clear();
      setState(() => _facilityExpanded = false);
      _showMessage('تم نشر المرفق');
      _reloadAssets();
    } catch (_) {
      _showMessage('تعذر نشر المرفق');
    }
  }

  Future<void> _submitProduct() async {
    final gymId = _selectedGymId;
    final title = _productTitleController.text.trim();

    if (gymId == null || title.isEmpty) {
      _showMessage('اختر النادي وأدخل عنوان المنتج');
      return;
    }

    final price = int.tryParse(_productPriceController.text.trim());

    try {
      await _api.createProduct(
        gymId: gymId,
        title: title,
        description: _productDescriptionController.text,
        price: price,
      );
      _productTitleController.clear();
      _productDescriptionController.clear();
      _productPriceController.clear();
      setState(() => _productExpanded = false);
      _showMessage('تم نشر المنتج');
      _reloadAssets();
    } catch (_) {
      _showMessage('تعذر نشر المنتج');
    }
  }

  Future<void> _saveGymProfile() async {
    final gymId = _selectedGymId;

    if (gymId == null) {
      _showMessage('اختر النادي أولاً');
      return;
    }

    try {
      await _api.updateGymProfile(
        gymId: gymId,
        audience: _selectedAudience,
        amenities: _selectedAmenities.toList(growable: false),
        openingHours: openingHoursToJson(_openingHours),
      );
      _showMessage('تم تحديث إعدادات النادي');
      setState(() {
        _profileGymId = null;
        _gymsFuture = _api.fetchOwnerGyms();
        _assetsFuture = _loadAssets(gymId);
      });
    } catch (_) {
      _showMessage('تعذر تحديث إعدادات النادي');
    }
  }

  Future<_StudioAssets> _loadAssets(String gymId) async {
    final detail = await _api.fetchGymDetail(gymId);
    return _StudioAssets(
      facilities: detail.facilities,
      products: detail.products,
    );
  }

  void _reloadGyms() {
    setState(() {
      _profileGymId = null;
      _gymsFuture = _api.fetchOwnerGyms();
    });
  }

  void _reloadAssets() {
    final gymId = _selectedGymId;
    if (gymId == null) {
      return;
    }

    setState(() {
      _assetsFuture = _loadAssets(gymId);
    });
  }

  Future<void> _refreshAll() async {
    setState(() {
      _gymsFuture = _api.fetchOwnerGyms();
      if (_selectedGymId != null) {
        _assetsGymId = _selectedGymId;
        _assetsFuture = _loadAssets(_selectedGymId!);
      }
    });

    await _gymsFuture;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _audienceLabel(String audience) {
    switch (audience) {
      case 'MEN_ONLY':
        return 'رجال فقط';
      case 'WOMEN_ONLY':
        return 'نساء فقط';
      default:
        return 'رجال ونساء';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Assets display — nicer cards for facilities & products
// ─────────────────────────────────────────────────────────────────────────────

class _AssetsDisplay extends StatelessWidget {
  const _AssetsDisplay({required this.assets, required this.context});
  final _StudioAssets assets;
  final BuildContext context;

  @override
  Widget build(BuildContext ctx) {
    final theme = Theme.of(ctx);
    final scheme = theme.colorScheme;

    Widget sectionHeader(String title, IconData icon) => Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Icon(icon, size: 18, color: scheme.primary),
          ],
        );

    Widget emptyCard(String msg) => Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outline),
          ),
          child: Text(msg,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        );

    Widget facilityCard(GymFacilityItem item) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outline),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.construction_outlined,
                    size: 16, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(item.name,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                        textAlign: TextAlign.end),
                    if (item.description != null &&
                        item.description!.isNotEmpty)
                      Text(item.description!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                          textAlign: TextAlign.end,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        );

    Widget productCard(GymProductItem item) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outline),
          ),
          child: Row(
            children: [
              if (item.price != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${item.price} د.ع',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      )),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(item.title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                        textAlign: TextAlign.end),
                    if (item.description != null &&
                        item.description!.isNotEmpty)
                      Text(item.description!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                          textAlign: TextAlign.end,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.storefront_outlined,
                    size: 16, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionHeader('المرافق المنشورة', Icons.construction_outlined),
        const SizedBox(height: 10),
        if (assets.facilities.isEmpty)
          emptyCard('لا توجد مرافق منشورة حالياً.')
        else
          ...assets.facilities.map(facilityCard),
        const SizedBox(height: 20),
        sectionHeader('المنتجات والإعلانات', Icons.storefront_outlined),
        const SizedBox(height: 10),
        if (assets.products.isEmpty)
          emptyCard('لا توجد منتجات منشورة حالياً.')
        else
          ...assets.products.map(productCard),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _AmenityTile extends StatelessWidget {
  const _AmenityTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.gold.withValues(alpha: 0.14)
              : const Color(0xFF1E1E35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppTheme.gold.withValues(alpha: 0.7)
                : const Color(0xFF2E2B4A),
            width: selected ? 1.5 : 1.0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppTheme.gold.withValues(alpha: 0.18),
                    blurRadius: 10,
                    spreadRadius: 0,
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.gold.withValues(alpha: 0.18)
                    : const Color(0xFF2A2840),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 18,
                color: selected ? AppTheme.gold : AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppTheme.gold : AppTheme.textSecondary,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _StudioAssets {
  const _StudioAssets({required this.facilities, required this.products});
  final List<GymFacilityItem> facilities;
  final List<GymProductItem> products;
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.error_outline, size: 42, color: Colors.red.shade700),
        const SizedBox(height: 10),
        const Text('تعذر تحميل نوادي المالك', textAlign: TextAlign.center),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      ],
    );
  }
}

// ── Opening hours row widget ────────────────────────────────────────────────
class _DayHoursRow extends StatelessWidget {
  const _DayHoursRow({
    required this.dayLabel,
    required this.enabled,
    required this.open,
    required this.close,
    required this.onToggle,
    required this.onOpenChanged,
    required this.onCloseChanged,
  });

  final String dayLabel;
  final bool enabled;
  final String open;
  final String close;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onOpenChanged;
  final ValueChanged<String> onCloseChanged;

  static const _times = [
    '00:00', '01:00', '02:00', '03:00', '04:00', '05:00',
    '06:00', '07:00', '08:00', '09:00', '10:00', '11:00',
    '12:00', '13:00', '14:00', '15:00', '16:00', '17:00',
    '18:00', '19:00', '20:00', '21:00', '22:00', '23:00',
    '23:59',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Switch.adaptive(
              value: enabled,
              activeTrackColor: AppTheme.gold,
              onChanged: onToggle,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 62,
            child: Text(
              dayLabel,
              style: TextStyle(
                color: enabled ? AppTheme.textPrimary : AppTheme.textMuted,
                fontSize: 13,
                fontWeight: enabled ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (enabled) ...[
            const SizedBox(width: 6),
            _TimePicker(
              value: open,
              onChanged: onOpenChanged,
              times: _times,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('–',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            ),
            _TimePicker(
              value: close,
              onChanged: onCloseChanged,
              times: _times,
            ),
          ] else ...[
            const Spacer(),
            Text('مغلق',
                style: TextStyle(
                    color: AppTheme.textMuted.withValues(alpha: 0.5),
                    fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _TimePicker extends StatelessWidget {
  const _TimePicker({
    required this.value,
    required this.onChanged,
    required this.times,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final List<String> times;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: times.contains(value) ? value : times.first,
          isDense: true,
          dropdownColor: const Color(0xFF1E1E35),
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
          iconEnabledColor: AppTheme.gold,
          iconSize: 16,
          items: times
              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
              .toList(growable: false),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
