import 'package:flutter/material.dart';

import '../../core/models/app_role.dart';
import 'marketplace_api_service.dart';
import 'marketplace_models.dart';

class OwnerStudioPage extends StatefulWidget {
  const OwnerStudioPage({super.key});

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

  late final MarketplaceApiService _api;
  late Future<List<GymSummary>> _gymsFuture;
  String? _selectedGymId;
  String? _assetsGymId;
  String? _profileGymId;
  String _selectedAudience = 'MIXED';
  Set<String> _selectedAmenities = <String>{};

  final TextEditingController _facilityNameController = TextEditingController();
  final TextEditingController _facilityDescriptionController = TextEditingController();
  final TextEditingController _productTitleController = TextEditingController();
  final TextEditingController _productDescriptionController = TextEditingController();
  final TextEditingController _productPriceController = TextEditingController();

  late Future<_StudioAssets> _assetsFuture;

  @override
  void initState() {
    super.initState();
    _api = MarketplaceApiService(role: AppRole.owner);
    _gymsFuture = _api.fetchOwnerGyms();
    _assetsFuture = Future.value(const _StudioAssets(facilities: [], products: []));
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
    return FutureBuilder<List<GymSummary>>(
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
            children: const [
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لا توجد نوادي مملوكة لك حالياً.'),
                ),
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
              Text('إدارة الاستوديو والمنتجات', style: Theme.of(context).textTheme.headlineSmall),
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
                  });
                },
              ),
              const SizedBox(height: 16),
              _buildGymProfileSettings(),
              const SizedBox(height: 14),
              _buildFacilityComposer(),
              const SizedBox(height: 14),
              _buildProductComposer(),
              const SizedBox(height: 16),
              FutureBuilder<_StudioAssets>(
                future: _assetsFuture,
                builder: (context, assetsSnapshot) {
                  if (assetsSnapshot.connectionState != ConnectionState.done) {
                    return const Center(child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ));
                  }

                  if (assetsSnapshot.hasError) {
                    return Card(
                      child: ListTile(
                        title: const Text('تعذر تحميل المرافق والمنتجات'),
                        trailing: TextButton(onPressed: _reloadAssets, child: const Text('إعادة')),
                      ),
                    );
                  }

                  final assets = assetsSnapshot.data ?? const _StudioAssets(facilities: [], products: []);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('المرافق المنشورة', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      if (assets.facilities.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(14),
                            child: Text('لا توجد مرافق منشورة حالياً.'),
                          ),
                        ),
                      ...assets.facilities.map(
                        (item) => Card(
                          child: ListTile(
                            title: Text(item.name),
                            subtitle: item.description == null ? null : Text(item.description!),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text('المنتجات والإعلانات', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      if (assets.products.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(14),
                            child: Text('لا توجد منتجات منشورة حالياً.'),
                          ),
                        ),
                      ...assets.products.map(
                        (item) => Card(
                          child: ListTile(
                            title: Text(item.title),
                            subtitle: Text(item.description ?? '-'),
                            trailing: Text(item.price == null ? '' : '${item.price} د.ع'),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGymProfileSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('إعدادات النادي', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _selectedAudience,
              decoration: const InputDecoration(labelText: 'فئة النادي'),
              items: _audiences
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item,
                      child: Text(_audienceLabel(item)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }

                setState(() {
                  _selectedAudience = value;
                });
              },
            ),
            const SizedBox(height: 10),
            Text('الخدمات المتوفرة', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _amenityPresets
                  .map(
                    (item) => FilterChip(
                      label: Text(item),
                      selected: _selectedAmenities.contains(item),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedAmenities.add(item);
                          } else {
                            _selectedAmenities.remove(item);
                          }
                        });
                      },
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _saveGymProfile,
              child: const Text('حفظ إعدادات النادي'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFacilityComposer() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('إضافة مرفق', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            TextField(
              controller: _facilityNameController,
              decoration: const InputDecoration(labelText: 'اسم المرفق'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _facilityDescriptionController,
              decoration: const InputDecoration(labelText: 'وصف المرفق'),
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: _submitFacility, child: const Text('نشر المرفق')),
          ],
        ),
      ),
    );
  }

  Widget _buildProductComposer() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('إضافة منتج/إعلان', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            TextField(
              controller: _productTitleController,
              decoration: const InputDecoration(labelText: 'عنوان المنتج'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _productDescriptionController,
              decoration: const InputDecoration(labelText: 'وصف المنتج'),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _productPriceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'السعر (اختياري)'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: _submitProduct, child: const Text('نشر المنتج')),
          ],
        ),
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

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
