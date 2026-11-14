import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const String envMapboxToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: '',
  );

  static const double abbottabadLat = 34.1688;
  static const double abbottabadLon = 73.2215;

  static Future<String> getEffectiveMapboxToken() async {
    if (envMapboxToken.isNotEmpty) return envMapboxToken;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('mapbox_public_token') ?? '';
  }

  static Future<void> saveMapboxToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mapbox_public_token', token.trim());
  }
}
