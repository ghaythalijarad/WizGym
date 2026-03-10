import 'package:flutter/widgets.dart';

class AppLocaleController extends ChangeNotifier {
  Locale _locale;

  AppLocaleController({Locale initialLocale = const Locale('ar')})
      : _locale = initialLocale;

  Locale get locale => _locale;

  bool get isArabic => _locale.languageCode.toLowerCase() == 'ar';

  void setLocale(Locale locale) {
    if (locale == _locale) return;
    _locale = locale;
    notifyListeners();
  }

  void toggle() {
    setLocale(isArabic ? const Locale('en') : const Locale('ar'));
  }
}
