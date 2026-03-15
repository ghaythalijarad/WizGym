import 'package:flutter/material.dart';

import '../../core/notifications/notification_model.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/theme/app_theme.dart';

/// App-bar action: animated bell icon with unread badge.
/// Tapping opens a bottom-sheet panel listing all notifications.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with SingleTickerProviderStateMixin {
  final _service = NotificationService.instance;
  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;
  int _prevUnread = 0;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 0.12), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.12, end: -0.12), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.12, end: 0.08), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.08, end: 0), weight: 1),
    ]).animate(_shakeCtrl);

    _prevUnread = _service.unreadCount;
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    final newUnread = _service.unreadCount;
    if (newUnread > _prevUnread) {
      _shakeCtrl.forward(from: 0);
    }
    _prevUnread = newUnread;
    setState(() {});
  }

  void _openPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NotificationPanel(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unread = _service.unreadCount;

    return AnimatedBuilder(
      animation: _shakeAnim,
      builder: (context, child) => Transform.rotate(
        angle: _shakeAnim.value,
        child: child,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: 'الإشعارات',
            onPressed: _openPanel,
            icon: Icon(
              unread > 0
                  ? Icons.notifications_rounded
                  : Icons.notifications_outlined,
              color: unread > 0
                  ? AppTheme.gold
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
          if (unread > 0)
            Positioned(
              top: 6,
              right: 6,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: AppTheme.cardPink,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 1.5,
                    ),
                  ),
                  constraints:
                      const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                      color: Color(0xFF1A1A24),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Bottom-sheet panel ─────────────────────────────────────────────────────

class _NotificationPanel extends StatefulWidget {
  const _NotificationPanel();

  @override
  State<_NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<_NotificationPanel> {
  final _service = NotificationService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_rebuild);
  }

  @override
  void dispose() {
    _service.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notifications = _service.notifications;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A24),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: Column(
            children: [
              // ── Handle ──
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // ── Header ──
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_rounded,
                        color: AppTheme.gold, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'الإشعارات',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: AppTheme.gold),
                    ),
                    const Spacer(),
                    if (notifications.any((n) => !n.isRead))
                      TextButton(
                        onPressed: () => _service.markAllRead(),
                        child: const Text('قراءة الكل',
                            style: TextStyle(
                                color: AppTheme.cardLavender, fontSize: 13)),
                      ),
                    if (notifications.isNotEmpty)
                      IconButton(
                        tooltip: 'مسح الكل',
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('مسح الإشعارات'),
                              content:
                                  const Text('هل تريد حذف جميع الإشعارات؟'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('إلغاء'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('حذف'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) await _service.clearAll();
                        },
                        icon: const Icon(Icons.delete_outline, size: 20),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // ── List ──
              Expanded(
                child: notifications.isEmpty
                    ? _EmptyState()
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: notifications.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 72, endIndent: 20),
                        itemBuilder: (context, i) =>
                            _NotificationTile(notification: notifications[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Single tile ────────────────────────────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final accent = notification.accentColor;
    final isUnread = !notification.isRead;

    return InkWell(
      onTap: () => NotificationService.instance.markRead(notification.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon bubble
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: accent.withValues(alpha: 0.25), width: 0.5),
              ),
              child: Icon(notification.icon, color: accent, size: 22),
            ),
            const SizedBox(width: 14),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: isUnread
                                        ? AppTheme.textPrimary
                                        : AppTheme.textSecondary,
                                    fontWeight: isUnread
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                        ),
                      ),
                      if (isUnread)
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: const BoxDecoration(
                            color: AppTheme.gold,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  if (notification.body.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      notification.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    notification.relativeTime,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: accent.withValues(alpha: 0.7),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.notifications_off_outlined,
              size: 56, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Text(
            'لا توجد إشعارات حالياً',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            'ستظهر هنا الإشعارات الجديدة تلقائياً',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
