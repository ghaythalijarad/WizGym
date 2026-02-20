enum AppRole {
  admin(labelAr: 'مدير المنصة'),
  owner(labelAr: 'مالك النادي'),
  trainer(labelAr: 'المدرب'),
  user(labelAr: 'المشترك');

  const AppRole({required this.labelAr});

  final String labelAr;
}
