# WizGym Mobile

Arabic-first Flutter application with role-specific navigation shells for:

- مدير المنصة (Platform Admin)
- مالك النادي (Gym Owner)
- المدرب (Trainer)
- المشترك (Member)

## Start

```bash
flutter pub get
flutter run
```

The app points to the live AWS Lambda API by default
(`https://3u10v51mvk.execute-api.us-east-1.amazonaws.com/api/v1`).
No local backend needed.

## Override API URL (optional)

```bash
flutter run --dart-define=API_BASE_URL=https://your-custom-url/api/v1/
```
