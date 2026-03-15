import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'marketplace_api_service.dart';

class OwnerGymPhotosSection extends StatefulWidget {
  const OwnerGymPhotosSection(
      {super.key, required this.gymId, required this.api});

  final String gymId;
  final MarketplaceApiService api;

  @override
  State<OwnerGymPhotosSection> createState() => _OwnerGymPhotosSectionState();
}

class _OwnerGymPhotosSectionState extends State<OwnerGymPhotosSection> {
  final ImagePicker _picker = ImagePicker();

  bool _busy = false;
  late Future<List<GymPhotoItem>> _photosFuture;

  @override
  void initState() {
    super.initState();
    _photosFuture = widget.api.fetchGymPhotos(widget.gymId);
  }

  Future<void> _reload() async {
    setState(() {
      _photosFuture = widget.api.fetchGymPhotos(widget.gymId);
    });
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    if (_busy) return;

    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 2000,
    );
    if (picked == null) return;

    setState(() => _busy = true);
    try {
      final file = File(picked.path);
      final bytes = await file.readAsBytes();

      final mime = _guessMime(picked.path);
      final presign = await widget.api.presignGymPhotoUpload(
        widget.gymId,
        contentType: mime,
      );

      // Upload to S3 using the pre-signed URL
      final putRes = await http.put(
        Uri.parse(presign.uploadUrl),
        headers: {
          'Content-Type': mime,
        },
        body: bytes,
      );

      if (putRes.statusCode < 200 || putRes.statusCode >= 300) {
        throw ApiException(putRes.statusCode, 'فشل رفع الصورة إلى التخزين');
      }

      // Register the URL in backend so it appears in gallery
      await widget.api.createGymPhoto(widget.gymId, url: presign.url);

      if (!mounted) return;
      await _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدث خطأ أثناء رفع الصورة')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deletePhoto(GymPhotoItem photo) async {
    if (_busy) return;

    setState(() => _busy = true);
    try {
      await widget.api.deleteGymPhoto(widget.gymId, photoId: photo.photoId);
      if (!mounted) return;
      await _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _resolveViewUrl(GymPhotoItem photo) async {
    try {
      return await widget.api.fetchGymPhotoViewUrl(
        widget.gymId,
        photoId: photo.photoId,
      );
    } catch (_) {
      // Fallback: if backend/view-url isn't available or fails, try the stored URL.
      return photo.url;
    }
  }

  String _guessMime(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return FutureBuilder<List<GymPhotoItem>>(
      future: _photosFuture,
      builder: (context, snapshot) {
        final photos = snapshot.data ?? const <GymPhotoItem>[];
        final isLoading = snapshot.connectionState != ConnectionState.done;
        final hasError = snapshot.hasError;
        const maxPhotos = 5;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ───────────────────────────────────────
              Row(
                children: [
                  if (_busy || isLoading)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: scheme.primary),
                    )
                  else if (hasError)
                    Icon(Icons.warning_amber_outlined,
                        size: 16, color: scheme.error),
                  const Spacer(),
                  Icon(Icons.photo_library_outlined,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    'صور الاستوديو',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ── Slots row ─────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(maxPhotos, (i) {
                  final filled = i < photos.length;
                  final photo = filled ? photos[i] : null;

                  return Expanded(
                    child: Padding(
                      padding:
                          EdgeInsets.only(right: i < maxPhotos - 1 ? 6 : 0),
                      child: _PhotoSlot(
                        filled: filled,
                        photo: photo,
                        busy: _busy,
                        index: i,
                        resolveUrl: photo != null ? _resolveViewUrl : null,
                        onDelete: photo != null
                            ? () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('حذف الصورة؟'),
                                    content: const Text(
                                        'سيتم حذف الصورة من معرض النادي.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(false),
                                        child: const Text('إلغاء'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(true),
                                        child: const Text('حذف'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) await _deletePhoto(photo);
                              }
                            : null,
                      ),
                    ),
                  );
                }),
              ),

              // ── Counter label ─────────────────────────────────
              const SizedBox(height: 8),
              Text(
                isLoading
                    ? 'جارٍ التحميل…'
                    : hasError
                        ? 'تعذر التحميل'
                        : '${photos.length} / $maxPhotos صور مرفوعة',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isLoading || hasError
                      ? scheme.onSurfaceVariant
                      : photos.length >= maxPhotos
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                ),
              ),

              // ── Upload buttons (only if below limit) ─────────
              if (!isLoading && !hasError && photos.length < maxPhotos) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _pickAndUpload(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined, size: 16),
                        label: const Text('كاميرا'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _pickAndUpload(ImageSource.gallery),
                        icon:
                            const Icon(Icons.photo_library_outlined, size: 16),
                        label: const Text('معرض'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (!isLoading &&
                  !hasError &&
                  photos.length >= maxPhotos) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 14, color: scheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      'اكتملت الصور — احذف لإضافة جديدة',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.primary),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single photo slot widget
// ─────────────────────────────────────────────────────────────────────────────

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    required this.filled,
    required this.index,
    required this.busy,
    this.photo,
    this.resolveUrl,
    this.onDelete,
  });

  final bool filled;
  final bool busy;
  final int index;
  final GymPhotoItem? photo;
  final Future<String> Function(GymPhotoItem)? resolveUrl;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Fixed square aspect ratio
    return AspectRatio(
      aspectRatio: 1,
      child: filled
          ? _FilledSlot(
              photo: photo!,
              resolveUrl: resolveUrl!,
              onDelete: busy ? null : onDelete,
              scheme: scheme,
            )
          : _EmptySlot(index: index, scheme: scheme),
    );
  }
}

class _FilledSlot extends StatelessWidget {
  const _FilledSlot({
    required this.photo,
    required this.resolveUrl,
    required this.scheme,
    this.onDelete,
  });

  final GymPhotoItem photo;
  final Future<String> Function(GymPhotoItem) resolveUrl;
  final ColorScheme scheme;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Filled circle indicator
        Container(
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.primary, width: 1.5),
          ),
          child: Icon(Icons.check_rounded,
              size: 20, color: scheme.onPrimaryContainer),
        ),
        // Delete button top-right
        if (onDelete != null)
          Positioned(
            top: -2,
            right: -2,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: scheme.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 1.5),
                ),
                child:
                    Icon(Icons.close_rounded, size: 11, color: scheme.onError),
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.index, required this.scheme});
  final int index;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.outlineVariant,
          width: 1.5,
        ),
      ),
      child: Center(
        child: Text(
          '${index + 1}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant, // #3D3852 — 9.2:1 on surfaceHigh ✓
          ),
        ),
      ),
    );
  }
}
