import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 6 separate digit boxes with auto-advance, auto-backspace, and paste support.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    required this.onCompleted,
    this.onChanged,
    this.length = 6,
  });

  final int length;
  final ValueChanged<String> onCompleted;
  final ValueChanged<String>? onChanged;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _currentValue => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    // Handle paste: value may be multiple chars
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'[^\d]'), '');
      for (int i = 0; i < widget.length && i < digits.length; i++) {
        _controllers[i].text = digits[i];
      }
      final nextEmpty =
          digits.length < widget.length ? digits.length : widget.length - 1;
      _focusNodes[nextEmpty].requestFocus();
      final full = _currentValue;
      widget.onChanged?.call(full);
      if (full.length == widget.length) widget.onCompleted(full);
      return;
    }

    if (value.isEmpty) {
      // Backspace: move back
      if (index > 0) {
        _controllers[index].clear();
        _focusNodes[index - 1].requestFocus();
      }
    } else {
      _controllers[index].text = value;
      _controllers[index].selection =
          TextSelection.collapsed(offset: value.length);
      if (index < widget.length - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
    }

    final full = _currentValue;
    widget.onChanged?.call(full);
    if (full.length == widget.length && !full.contains('')) {
      widget.onCompleted(full);
    }
  }

  void clear() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes[0].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(widget.length, (i) {
          final hasFocus = _focusNodes[i].hasFocus;
          final hasValue = _controllers[i].text.isNotEmpty;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: 48,
            height: 58,
            decoration: BoxDecoration(
              color: hasValue
                  ? scheme.primary.withValues(alpha: 0.1)
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasFocus
                    ? scheme.primary
                    : hasValue
                        ? scheme.primary.withValues(alpha: 0.5)
                        : scheme.outline,
                width: hasFocus ? 2 : 1.2,
              ),
              boxShadow: hasFocus
                  ? [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: TextFormField(
              controller: _controllers[i],
              focusNode: _focusNodes[i],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 2, // allow 2 so we can detect paste vs single digit
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: hasValue ? scheme.primary : scheme.onSurface,
                letterSpacing: 0,
              ),
              decoration: const InputDecoration(
                counterText: '',
                contentPadding: EdgeInsets.zero,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: (v) => _onDigitChanged(i, v),
            ),
          );
        }),
      ),
    );
  }
}
