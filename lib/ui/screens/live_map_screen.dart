import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../../core/app_config.dart';
import '../../services/native_tracker_bridge.dart';

class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  MapboxMap? _mapboxMap;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Map<String, dynamic> _telemetry = {
    'status': 'IDLE',
    'steps': 0,
    'distanceMeters': 0.0,
    'movingDurationMs': 0,
    'cadenceSpm': 0.0,
    'latitude': AppConfig.abbottabadLat,
    'longitude': AppConfig.abbottabadLon,
    'accuracyMeters': 0.0,
    'currentHexId': 'h3r9_0_0',
    'visitedHexCount': 0,
    'polylines': [],
    'hexPolygons': [],
  };

  bool _followUser = true;
  bool _is3DPitch = false;
  String _currentStyle = MapboxStyles.OUTDOORS;
  bool _layersInitialized = false;

  @override
  void initState() {
    super.initState();
    _sub = NativeTrackerBridge.telemetryStream.listen((data) {
      if (!mounted) return;
      setState(() => _telemetry = data);
      _updateMapLayersAndCamera(data);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    await mapboxMap.location.updateSettings(
      LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
        showAccuracyRing: true,
      ),
    );
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData event) async {
    final map = _mapboxMap;
    if (map == null) return;
    _layersInitialized = false;

    try {
      await map.style.addSource(
        GeoJsonSource(
          id: 'hex-grid-source',
          data: jsonEncode({'type': 'FeatureCollection', 'features': []}),
        ),
      );
      await map.style.addLayer(
        FillLayer(
          id: 'hex-grid-fill',
          sourceId: 'hex-grid-source',
          fillColor: 0xFF10B981,
          fillOpacity: 0.28,
        ),
      );
      await map.style.addLayer(
        LineLayer(
          id: 'hex-grid-outline',
          sourceId: 'hex-grid-source',
          lineColor: 0xFF047857,
          lineWidth: 2.0,
        ),
      );

      await map.style.addSource(
        GeoJsonSource(
          id: 'walk-route-source',
          data: jsonEncode({'type': 'FeatureCollection', 'features': []}),
        ),
      );
      await map.style.addLayer(
        LineLayer(
          id: 'walk-route-layer',
          sourceId: 'walk-route-source',
          lineColor: 0xFF10B981,
          lineWidth: 5.5,
          lineCap: LineCap.ROUND,
          lineJoin: LineJoin.ROUND,
        ),
      );
      _layersInitialized = true;
      await _updateMapLayersAndCamera(_telemetry);
    } catch (_) {}
  }

  Future<void> _updateMapLayersAndCamera(Map<String, dynamic> data) async {
    final map = _mapboxMap;
    if (map == null || !_layersInitialized) return;

    final rawPolylines = (data['polylines'] as List?) ?? [];
    final multiLineCoords = rawPolylines
        .map((seg) => (seg as List)
            .map((pt) => [(pt as List)[0] as num, pt[1] as num])
            .toList())
        .where((seg) => seg.length >= 2)
        .toList();

    final routeGeoJson = {
      'type': 'FeatureCollection',
      'features': [
        if (multiLineCoords.isNotEmpty)
          {
            'type': 'Feature',
            'geometry': {
              'type': 'MultiLineString',
              'coordinates': multiLineCoords,
            },
            'properties': {},
          }
      ],
    };

    final rawHexes = (data['hexPolygons'] as List?) ?? [];
    final hexFeatures = rawHexes.map((h) {
      final hMap = Map<String, dynamic>.from(h as Map);
      final ring = (hMap['ring'] as List)
          .map((pt) => [(pt as List)[0] as num, pt[1] as num])
          .toList();
      return {
        'type': 'Feature',
        'geometry': {
          'type': 'Polygon',
          'coordinates': [ring],
        },
        'properties': {'hexId': hMap['hexId']},
      };
    }).toList();

    final hexGeoJson = {
      'type': 'FeatureCollection',
      'features': hexFeatures,
    };

    try {
      await map.style.setStyleSourceProperty('walk-route-source', 'data', jsonEncode(routeGeoJson));

      await map.style.setStyleSourceProperty('hex-grid-source', 'data', jsonEncode(hexGeoJson));
    } catch (_) {}

    if (_followUser) {
      final lat = (data['latitude'] as num?)?.toDouble() ?? AppConfig.abbottabadLat;
      final lon = (data['longitude'] as num?)?.toDouble() ?? AppConfig.abbottabadLon;
      await map.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(lon, lat)),
          zoom: 16.2,
          pitch: _is3DPitch ? 45.0 : 0.0,
        ),
        MapAnimationOptions(duration: 500),
      );
    }
  }

  String _formatDuration(int ms) {
    final totalSec = ms ~/ 1000;
    final mins = (totalSec ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSec % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  void _cycleStyle() {
    final styles = [
      MapboxStyles.OUTDOORS,
      MapboxStyles.DARK,
      MapboxStyles.SATELLITE_STREETS,
      MapboxStyles.STANDARD,
    ];
    final nextIdx = (styles.indexOf(_currentStyle) + 1) % styles.length;
    setState(() => _currentStyle = styles[nextIdx]);
    _mapboxMap?.loadStyleURI(_currentStyle);
  }

  @override
  Widget build(BuildContext context) {
    final status = (_telemetry['status'] as String?) ?? 'IDLE';
    final steps = (_telemetry['steps'] as num?)?.toInt() ?? 0;
    final distM = (_telemetry['distanceMeters'] as num?)?.toDouble() ?? 0.0;
    final movingMs = (_telemetry['movingDurationMs'] as num?)?.toInt() ?? 0;
    final cadence = (_telemetry['cadenceSpm'] as num?)?.toDouble() ?? 0.0;
    final accM = (_telemetry['accuracyMeters'] as num?)?.toDouble() ?? 0.0;
    final hexId = (_telemetry['currentHexId'] as String?) ?? 'h3r9_0_0';
    final hexCount = (_telemetry['visitedHexCount'] as num?)?.toInt() ?? 0;

    return Scaffold(
      body: Stack(
        children: [
          MapWidget(
            key: const ValueKey('terrastep_mapbox_map'),
            styleUri: _currentStyle,
            cameraOptions: CameraOptions(
              center: Point(
                coordinates: Position(
                  AppConfig.abbottabadLon,
                  AppConfig.abbottabadLat,
                ),
              ),
              zoom: 15.5,
            ),
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: _onStyleLoaded,
          ),

          // Top Telemetry Pill
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xDD0F172A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.gps_fixed, color: Color(0xFF10B981), size: 18),
                              const SizedBox(width: 6),
                              Text(
                                accM > 0 ? 'GPS ±${accM.toStringAsFixed(1)}m' : 'GPS Ready',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ],
                          ),
                          Text(
                            'Hex: $hexId ($hexCount)',
                            style: const TextStyle(color: Color(0xFF34D399), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Right-Side Floating Map API Controls
          Positioned(
            right: 12,
            top: 90,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'follow_btn',
                  backgroundColor: _followUser ? const Color(0xFF059669) : const Color(0xDD0F172A),
                  onPressed: () {
                    setState(() => _followUser = !_followUser);
                    if (_followUser) _updateMapLayersAndCamera(_telemetry);
                  },
                  child: Icon(_followUser ? Icons.my_location : Icons.location_searching),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'pitch_btn',
                  backgroundColor: _is3DPitch ? const Color(0xFF059669) : const Color(0xDD0F172A),
                  onPressed: () {
                    setState(() => _is3DPitch = !_is3DPitch);
                    _updateMapLayersAndCamera(_telemetry);
                  },
                  child: const Text('3D', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'style_btn',
                  backgroundColor: const Color(0xDD0F172A),
                  onPressed: _cycleStyle,
                  child: const Icon(Icons.layers),
                ),
              ],
            ),
          ),

          // Bottom Recorder & Step Counter HUD
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xF00F172A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _MetricTile(
                        label: 'STEPS',
                        value: '$steps',
                        icon: Icons.directions_walk,
                        accent: const Color(0xFF10B981),
                      ),
                      _MetricTile(
                        label: 'DISTANCE',
                        value: '${(distM / 1000.0).toStringAsFixed(2)} km',
                        icon: Icons.straighten,
                      ),
                      _MetricTile(
                        label: 'MOVING TIME',
                        value: _formatDuration(movingMs),
                        icon: Icons.timer_outlined,
                      ),
                      _MetricTile(
                        label: 'CADENCE',
                        value: '${cadence.toStringAsFixed(0)} spm',
                        icon: Icons.speed,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (status == 'IDLE')
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => NativeTrackerBridge.startWalk(),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text(
                          'Start Walk (Step + GPS + GPX)',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                if (status == 'RECORDING') {
                                  NativeTrackerBridge.pauseWalk();
                                } else {
                                  NativeTrackerBridge.resumeWalk();
                                }
                              },
                              icon: Icon(status == 'RECORDING' ? Icons.pause : Icons.play_arrow),
                              label: Text(status == 'RECORDING' ? 'Pause' : 'Resume'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFDC2626),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () async {
                                final res = await NativeTrackerBridge.finishWalk();
                                if (!context.mounted) return;
                                final path = res['gpxFilePath'] ?? '';
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Saved GPX (${res['totalSteps']} steps): $path'),
                                    duration: const Duration(seconds: 4),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.stop),
                              label: const Text('Finish & Save GPX'),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? accent;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: accent ?? Colors.white70),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: accent ?? Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.white60),
        ),
      ],
    );
  }
}
