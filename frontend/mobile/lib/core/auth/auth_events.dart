import 'dart:async';

/// Global event bus for auth-related events (e.g. 401 from backend).
///
/// API services call [AuthEvents.emitUnauthorized] when they receive
/// HTTP 401. The app root listens and triggers a logout + re-login flow.
class AuthEvents {
  AuthEvents._();

  static final _controller = StreamController<void>.broadcast();

  /// Stream that fires when any API call receives a 401 Unauthorized.
  static Stream<void> get onUnauthorized => _controller.stream;

  /// Call this from any API service when a 401 is received.
  static void emitUnauthorized() {
    _controller.add(null);
  }
}
