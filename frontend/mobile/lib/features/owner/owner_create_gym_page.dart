import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';
import '../marketplace/marketplace_api_service.dart';
import '../marketplace/marketplace_models.dart';

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
  final Map<String, DayHours> _openingHours = {};
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
        openingHours: openingHoursToJson(_openingHours),
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

          // ── Opening hours ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.schedule_rounded,
                          size: 18, color: AppTheme.gold),
                      const SizedBox(width: 8),
                      Text('أوقات الدوام',
                          style: Theme.of(context).textTheme.titleSmall),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...kWeekDayKeys.map((day) {
                    final label = kWeekDayLabelsAr[day] ?? day;
                    final hours = _openingHours[day];
                    final enabled = hours != null;
                    return _CreateDayHoursRow(
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

// ── Opening hours row for create gym page ───────────────────────────────────
class _CreateDayHoursRow extends StatelessWidget {
  const _CreateDayHoursRow({
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
                color: enabled ? Colors.white : Colors.grey,
                fontSize: 13,
                fontWeight: enabled ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (enabled) ...[
            const SizedBox(width: 6),
            _CreateTimePicker(value: open, onChanged: onOpenChanged, times: _times),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('–', style: TextStyle(color: Colors.grey, fontSize: 13)),
            ),
            _CreateTimePicker(value: close, onChanged: onCloseChanged, times: _times),
          ] else ...[
            const Spacer(),
            const Text('مغلق', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _CreateTimePicker extends StatelessWidget {
  const _CreateTimePicker({
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade600),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: times.contains(value) ? value : times.first,
          isDense: true,
          style: const TextStyle(fontSize: 13),
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
