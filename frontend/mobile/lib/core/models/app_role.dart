enum AppRole {
  admin(labelAr: 'مدير المنصة', apiValue: 'ADMIN'),
  owner(labelAr: 'مالك النادي', apiValue: 'OWNER'),
  trainer(labelAr: 'المدرب', apiValue: 'TRAINER'),
  user(labelAr: 'المشترك', apiValue: 'USER'),

  /// Alias kept for compatibility – same as [user].
  trainee(labelAr: 'المشترك', apiValue: 'USER');

  const AppRole({required this.labelAr, required this.apiValue});

  final String labelAr;
  final String apiValue;

  static AppRole fromApi(String value) {
    switch (value.toUpperCase()) {
      case 'ADMIN':
        return AppRole.admin;
      case 'OWNER':
        return AppRole.owner;
      case 'TRAINER':
        return AppRole.trainer;
      case 'TRAINEE':
      case 'USER':
      default:
        return AppRole.user;
    }
  }
}
