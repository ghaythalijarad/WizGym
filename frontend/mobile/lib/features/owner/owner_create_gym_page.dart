import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/app_role.dart';
import '../marketplace/marketplace_api_service.dart';

class OwnerCreateGymPage extends StatefulWidget {
  const OwnerCreateGymPage({super.key, this.session});

  final AuthSession? session;

  @override
  State<OwnerCreateGymPage> createState() => _OwnerCreateGymPageState();
}

class _OwnerCreateGymPageState extends State<OwnerCreateGymPage> {
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

  final _nameController = TextEditingController();
  final _cityController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _audience = 'MIXED';
  final Set<String> _amenities = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _api = MarketplaceApiService(role: AppRole.owner, session: widget.session);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final city = _cityController.text.trim();
    if (name.isEmpty || city.isEmpty) {
      _showMsg('يرجى إدخال اسم النادي والمدينة');
      return;
    }

    // Plans are now managed after gym creation (from gym details).

    setState(() => _isSubmitting = true);

    try {
      await _api.createGym(
        name: name,
        city: city,
        description: _descriptionController.text,
        audience: _audience,
        amenities: _amenities.toList(growable: false),
        subscriptionPlans: const [],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم إنشاء النادي بنجاح — يمكنك الآن إضافة خطط الاشتراك من صفحة خطط النادي ✓')),
        );
        Navigator.of(context).pop(true); // signal success
      }
    } catch (e) {
      _showMsg('تعذر إنشاء النادي: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showMsg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إنشاء نادي جديد')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Basic info ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('معلومات النادي',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    decoration:
                        const InputDecoration(labelText: 'اسم النادي *'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _cityController,
                    decoration: const InputDecoration(labelText: 'المدينة *'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'وصف النادي'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _audience,
                    decoration: const InputDecoration(labelText: 'الفئة'),
                    items: _audiences
                        .map((a) => DropdownMenuItem(
                            value: a, child: Text(_audienceLabel(a))))
                        .toList(growable: false),
                    onChanged: (v) {
                      if (v != null) setState(() => _audience = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text('الخدمات المتوفرة',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _amenityPresets
                        .map((a) => FilterChip(
                              label: Text(a),
                              selected: _amenities.contains(a),
                              onSelected: (s) => setState(() {
                                if (s) {
                                  _amenities.add(a);
                                } else {
                                  _amenities.remove(a);
                                }
                              }),
                            ))
                        .toList(growable: false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // ── Subscription Plans ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('خطط الاشتراك',
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'بعد إنشاء النادي، يمكنك إضافة/تعديل خطط الاشتراك من تبويب (الخطط).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // ── Pending note ──
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'ملاحظة: سيظهر النادي للمتدربين بعد اعتماده من مدير المنصة.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Submit ──
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: Text(_isSubmitting ? 'جارٍ الإرسال...' : 'إنشاء النادي'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
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
