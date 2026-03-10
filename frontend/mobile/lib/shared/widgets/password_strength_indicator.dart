import 'package:flutter/material.dart';

enum PasswordStrength { weak, fair, good, strong }

/// Visual password strength indicator with animated bars.
class PasswordStrengthIndicator extends StatelessWidget {
  const PasswordStrengthIndicator({
    super.key,
    required this.password,
    this.isArabic = true,
  });

  final String password;
  final bool isArabic;

  PasswordStrength get _strength {
    if (password.isEmpty) return PasswordStrength.weak;

    int score = 0;

    // Length check
    if (password.length >= 6) score++;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;

    // Contains number
    if (password.contains(RegExp(r'[0-9]'))) score++;

    // Contains lowercase
    if (password.contains(RegExp(r'[a-z]'))) score++;

    // Contains uppercase
    if (password.contains(RegExp(r'[A-Z]'))) score++;

    // Contains special char
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) score++;

    if (score <= 2) return PasswordStrength.weak;
    if (score <= 4) return PasswordStrength.fair;
    if (score <= 5) return PasswordStrength.good;
    return PasswordStrength.strong;
  }

  Color _colorForStrength(ColorScheme scheme) {
    switch (_strength) {
      case PasswordStrength.weak:
        return scheme.error;
      case PasswordStrength.fair:
        return Colors.orange;
      case PasswordStrength.good:
        return scheme.secondary;
      case PasswordStrength.strong:
        return scheme.primary;
    }
  }

  String _labelForStrength() {
    if (isArabic) {
      switch (_strength) {
        case PasswordStrength.weak:
          return 'ضعيفة';
        case PasswordStrength.fair:
          return 'مقبولة';
        case PasswordStrength.good:
          return 'جيدة';
        case PasswordStrength.strong:
          return 'قوية';
      }
    } else {
      switch (_strength) {
        case PasswordStrength.weak:
          return 'Weak';
        case PasswordStrength.fair:
          return 'Fair';
        case PasswordStrength.good:
          return 'Good';
        case PasswordStrength.strong:
          return 'Strong';
      }
    }
  }

  int get _filledBars {
    switch (_strength) {
      case PasswordStrength.weak:
        return 1;
      case PasswordStrength.fair:
        return 2;
      case PasswordStrength.good:
        return 3;
      case PasswordStrength.strong:
        return 4;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final color = _colorForStrength(scheme);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: List.generate(4, (index) {
                final filled = index < _filledBars;
                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: EdgeInsets.only(right: index < 3 ? 4 : 0),
                    height: 4,
                    decoration: BoxDecoration(
                      color: filled ? color : scheme.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _labelForStrength(),
              key: ValueKey(_strength),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
