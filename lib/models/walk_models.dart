/// Dart models mirroring the Kotlin telemetry / Room payloads.
/// Keys match WalkRecorderService.buildTelemetryPayload() and MainActivity
/// getSavedSessions / getSessionDetail exactly.

class TelemetryState {
  final String? sessionId;
  final String status; // IDLE | RECORDING | PAUSED
  final int elapsedDurationMs;
  final int movingDurationMs;
  final int steps;
  final int rawBootSteps;
  final double cadenceSpm;
  final double distanceMeters;
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final String currentHexId;
  final int visitedHexCount;

  /// List of segments; each segment is a list of [lon, lat] pairs.
  final List<List<List<double>>> polylines;

  /// Hex polygons: each has hexId + ring of [lon, lat] pairs (closed).
  final List<HexPolygon> hexPolygons;
  final bool hasStepSensor;

  const TelemetryState({
    this.sessionId,
    this.status = 'IDLE',
    this.elapsedDurationMs = 0,
    this.movingDurationMs = 0,
    this.steps = 0,
    this.rawBootSteps = 0,
    this.cadenceSpm = 0.0,
    this.distanceMeters = 0.0,
    this.latitude = 34.1688,
    this.longitude = 73.2215,
    this.accuracyMeters = 0.0,
    this.currentHexId = 'h3r9_0_0',
    this.visitedHexCount = 0,
    this.polylines = const [],
    this.hexPolygons = const [],
    this.hasStepSensor = false,
  });

  bool get isRecording => status == 'RECORDING';
  bool get isPaused => status == 'PAUSED';
  bool get isActive => isRecording || isPaused;

  factory TelemetryState.fromMap(Map<String, dynamic> m) {
    final rawPolylines = (m['polylines'] as List?) ?? const [];
    final polylines = <List<List<double>>>[];
    for (final seg in rawPolylines) {
      final points = <List<double>>[];
      if (seg is List) {
        for (final p in seg) {
          if (p is List && p.length >= 2) {
            points.add([(p[0] as num).toDouble(), (p[1] as num).toDouble()]);
          }
        }
      }
      if (points.isNotEmpty) polylines.add(points);
    }

    final rawHex = (m['hexPolygons'] as List?) ?? const [];
    final hexPolygons = <HexPolygon>[];
    for (final h in rawHex) {
      if (h is Map) {
        final ringRaw = (h['ring'] as List?) ?? const [];
        final ring = <List<double>>[];
        for (final p in ringRaw) {
          if (p is List && p.length >= 2) {
            ring.add([(p[0] as num).toDouble(), (p[1] as num).toDouble()]);
          }
        }
        if (ring.isNotEmpty) {
          hexPolygons.add(HexPolygon(hexId: (h['hexId'] ?? '').toString(), ring: ring));
        }
      }
    }

    return TelemetryState(
      sessionId: m['sessionId']?.toString(),
      status: (m['status'] ?? 'IDLE').toString(),
      elapsedDurationMs: _toInt(m['elapsedDurationMs']),
      movingDurationMs: _toInt(m['movingDurationMs']),
      steps: _toInt(m['steps']),
      rawBootSteps: _toInt(m['rawBootSteps']),
      cadenceSpm: _toDouble(m['cadenceSpm']),
      distanceMeters: _toDouble(m['distanceMeters']),
      latitude: _toDouble(m['latitude'], 34.1688),
      longitude: _toDouble(m['longitude'], 73.2215),
      accuracyMeters: _toDouble(m['accuracyMeters']),
      currentHexId: (m['currentHexId'] ?? 'h3r9_0_0').toString(),
      visitedHexCount: _toInt(m['visitedHexCount']),
      polylines: polylines,
      hexPolygons: hexPolygons,
      hasStepSensor: (m['hasStepSensor'] as bool?) ?? false,
    );
  }

  /// GeoJSON MultiLineString coordinates for the route layer.
  List<List<List<double>>> get routeCoordinates => polylines;

  static int _toInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  static double _toDouble(dynamic v, [double fallback = 0.0]) {
    if (v == null) return fallback;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }
}

class HexPolygon {
  final String hexId;
  final List<List<double>> ring; // [lon, lat] pairs, closed

  const HexPolygon({required this.hexId, required this.ring});
}

class WalkSession {
  final String sessionId;
  final String title;
  final int startTimeUtcMs;
  final int? endTimeUtcMs;
  final int elapsedDurationMs;
  final int movingDurationMs;
  final int totalSteps;
  final double totalDistanceMeters;
  final String visitedHexIdsJson;
  final String? gpxFilePath;
  final String status;

  const WalkSession({
    required this.sessionId,
    required this.title,
    required this.startTimeUtcMs,
    this.endTimeUtcMs,
    this.elapsedDurationMs = 0,
    this.movingDurationMs = 0,
    this.totalSteps = 0,
    this.totalDistanceMeters = 0.0,
    this.visitedHexIdsJson = '[]',
    this.gpxFilePath,
    this.status = 'COMPLETED',
  });

  factory WalkSession.fromMap(Map<String, dynamic> m) {
    return WalkSession(
      sessionId: (m['sessionId'] ?? '').toString(),
      title: (m['title'] ?? 'Walk').toString(),
      startTimeUtcMs: TelemetryState._toInt(m['startTimeUtcMs']),
      endTimeUtcMs: m['endTimeUtcMs'] == null
          ? null
          : TelemetryState._toInt(m['endTimeUtcMs']),
      elapsedDurationMs: TelemetryState._toInt(m['elapsedDurationMs']),
      movingDurationMs: TelemetryState._toInt(m['movingDurationMs']),
      totalSteps: TelemetryState._toInt(m['totalSteps']),
      totalDistanceMeters: TelemetryState._toDouble(m['totalDistanceMeters']),
      visitedHexIdsJson: (m['visitedHexIdsJson'] ?? '[]').toString(),
      gpxFilePath: m['gpxFilePath']?.toString(),
      status: (m['status'] ?? 'COMPLETED').toString(),
    );
  }

  DateTime get startDateTime =>
      DateTime.fromMillisecondsSinceEpoch(startTimeUtcMs, isUtc: true).toLocal();
}

class TrackPoint {
  final double lat;
  final double lon;
  final double ele;
  final int steps;
  final int segmentIndex;
  final String hexId;

  const TrackPoint({
    required this.lat,
    required this.lon,
    required this.ele,
    required this.steps,
    required this.segmentIndex,
    required this.hexId,
  });

  factory TrackPoint.fromMap(Map<String, dynamic> m) {
    return TrackPoint(
      lat: TelemetryState._toDouble(m['lat']),
      lon: TelemetryState._toDouble(m['lon']),
      ele: TelemetryState._toDouble(m['ele']),
      steps: TelemetryState._toInt(m['steps']),
      segmentIndex: TelemetryState._toInt(m['segmentIndex']),
      hexId: (m['hexId'] ?? '').toString(),
    );
  }
}

class SessionDetail {
  final String sessionId;
  final String gpxXml;
  final String gpxFilePath;
  final int pointCount;
  final List<TrackPoint> points;
  final List<HexPolygon> hexPolygons;

  const SessionDetail({
    required this.sessionId,
    required this.gpxXml,
    required this.gpxFilePath,
    required this.pointCount,
    required this.points,
    required this.hexPolygons,
  });

  factory SessionDetail.fromMap(Map<String, dynamic> m) {
    final rawPoints = (m['points'] as List?) ?? const [];
    final points = rawPoints
        .whereType<Map>()
        .map((e) => TrackPoint.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    final rawHex = (m['hexPolygons'] as List?) ?? const [];
    final hexPolygons = <HexPolygon>[];
    for (final h in rawHex) {
      if (h is Map) {
        final ringRaw = (h['ring'] as List?) ?? const [];
        final ring = <List<double>>[];
        for (final p in ringRaw) {
          if (p is List && p.length >= 2) {
            ring.add([(p[0] as num).toDouble(), (p[1] as num).toDouble()]);
          }
        }
        if (ring.isNotEmpty) {
          hexPolygons.add(HexPolygon(hexId: (h['hexId'] ?? '').toString(), ring: ring));
        }
      }
    }
    return SessionDetail(
      sessionId: (m['sessionId'] ?? '').toString(),
      gpxXml: (m['gpxXml'] ?? '').toString(),
      gpxFilePath: (m['gpxFilePath'] ?? '').toString(),
      pointCount: TelemetryState._toInt(m['pointCount'], points.length),
      points: points,
      hexPolygons: hexPolygons,
    );
  }
}

/// MM:SS formatter for HUD timers.
String formatMmSs(int ms) {
  final totalSec = (ms / 1000).floor();
  final mm = (totalSec / 60).floor().toString().padLeft(2, '0');
  final ss = (totalSec % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}

/// Distance formatter: metres below 1 km, kilometres above.
String formatDistance(double meters) {
  if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
  return '${(meters / 1000).toStringAsFixed(2)} km';
}
