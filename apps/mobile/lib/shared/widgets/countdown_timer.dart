import 'dart:async';
import 'package:flutter/material.dart';

/// Countdown timer widget for OTP resend functionality.
class CountdownTimer extends StatefulWidget {
  const CountdownTimer({
    super.key,
    required this.durationSeconds,
    required this.onComplete,
    this.onResend,
  });

  final int durationSeconds;
  final VoidCallback onComplete;
  final VoidCallback? onResend;

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer> {
  late int _secondsRemaining;
  Timer? _timer;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _secondsRemaining = widget.durationSeconds;
    _canResend = false;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
        setState(() => _canResend = true);
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void reset() {
    _startTimer();
    setState(() {});
  }

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF00A68C);
    const darkCard = Color(0xFF111C2E);

    if (_canResend) {
      return GestureDetector(
        onTap: () {
          widget.onResend?.call();
          _startTimer();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: darkCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: green.withValues(alpha: 0.5), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.refresh_rounded, size: 18, color: green),
              const SizedBox(width: 8),
              Text(
                'إعادة إرسال الرمز',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: green,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: green.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.timer_outlined,
            size: 18,
            color: green,
          ),
          const SizedBox(width: 8),
          Text(
            _formatTime(_secondsRemaining),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: green,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'للإعادة',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white54,
                ),
          ),
        ],
      ),
    );
  }
}
