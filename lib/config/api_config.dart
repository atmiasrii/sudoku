/// Single source of truth for the backend address. REST and the matchmaking
/// socket are served by the SAME process on the SAME port (see backend/server.js),
/// so they MUST point at the same host:port — keeping them here stops the two
/// from drifting apart (the previous bug: REST on 10.0.2.2:4001 while the socket
/// was on 192.168.0.40:7777, so REST was unreachable on a physical device).
///
/// [_host] must be reachable from the target device:
///   - Physical device: the dev machine's LAN IP (e.g. 192.168.0.40); the phone
///     must be on the same Wi-Fi.
///   - Android emulator: the LAN IP also works (10.0.2.2 is the emulator-only
///     loopback alias to the host).
/// Find your PC's LAN IP with `ipconfig` (IPv4 Address). Override without
/// editing code via: flutter run --dart-define=BACKEND_HOST=... --dart-define=BACKEND_PORT=...
class ApiConfig {
  ApiConfig._();

  static const String _host = String.fromEnvironment(
    'BACKEND_HOST',
    defaultValue: '192.168.0.40',
  );

  static const int _port = int.fromEnvironment(
    'BACKEND_PORT',
    defaultValue: 7777,
  );

  static const String _scheme = String.fromEnvironment(
    'BACKEND_SCHEME',
    defaultValue: 'http',
  );

  static String get socketUrl => '$_scheme://$_host:$_port';
  static String get apiBaseUrl => '$socketUrl/api';
}
