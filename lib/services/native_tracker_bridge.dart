import 'package:flutter/services.dart';

class NativeTrackerBridge {
  static const MethodChannel _methods = MethodChannel('com.terrastep.fyp/methods');
  static const EventChannel _telemetry = EventChannel('com.terrastep.fyp/telemetry');

  static Stream<Map<String, dynamic>> get telemetryStream =>
      _telemetry.receiveBroadcastStream().map((event) => Map<String, dynamic>.from(event as Map));

  static Future<void> startLocationPreview() async {
    await _methods.invokeMethod('startLocationPreview');
  }

  static Future<void> stopLocationPreview() async {
    await _methods.invokeMethod('stopLocationPreview');
  }

  static Future<Map<String, dynamic>> getDiagnostics() async {
    final res = await _methods.invokeMethod('getDiagnostics');
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<Map<String, dynamic>> startWalk() async {
    final res = await _methods.invokeMethod('startWalk');
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<Map<String, dynamic>> pauseWalk() async {
    final res = await _methods.invokeMethod('pauseWalk');
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<Map<String, dynamic>> resumeWalk() async {
    final res = await _methods.invokeMethod('resumeWalk');
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<Map<String, dynamic>> finishWalk() async {
    final res = await _methods.invokeMethod('finishWalk');
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<List<Map<String, dynamic>>> getSavedSessions() async {
    final res = await _methods.invokeMethod('getSavedSessions') as List;
    return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> getSessionDetail(String sessionId) async {
    final res = await _methods.invokeMethod('getSessionDetail', {'sessionId': sessionId});
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<String> exportToDownloads(String sessionId) async {
    final res = await _methods.invokeMethod('exportToDownloads', {'sessionId': sessionId});
    return res as String;
  }

  static Future<Map<String, dynamic>> generateDemoWalk() async {
    final res = await _methods.invokeMethod('generateDemoWalk');
    return Map<String, dynamic>.from(res as Map);
  }
}
