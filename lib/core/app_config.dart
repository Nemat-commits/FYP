import 'package:shared_preferences/shared_preferences.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class AppConfig {
  static const String mapboxPublicToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: '',
  );

  static const double abbottabadLat = 34.1688;
  static const double abbottabadLon = 73.2215;

  static Future<String> getEffectiveMapboxToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('mapbox_public_token') ?? mapboxPublicToken;
  }

  static Future<void> saveMapboxToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mapbox_public_token', token.trim());
  }

  static void initializeMapbox() {
    MapboxOptions.setAccessToken(mapboxPublicToken);
  }
}
