import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_config.dart';
import '../../models/walk_models.dart';
import '../../state/walk_providers.dart';

/// Live Mapbox canvas with emerald route polyline + H3 hex overlay (Blueprint 5.3).
class LiveMapScreen extends ConsumerStatefulWidget {
  const LiveMapScreen({super.key});

  @override
  ConsumerState<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends ConsumerState<LiveMapScreen> {
  MapboxMap? _map;
  bool _styleReady = false;
  bool _follow = true;
  double _pitch = 0;
  String _styleUri = MapboxStyles.OUTDOORS;
  String? _token;
  bool _busy = false;

  static const _routeSourceId = 'walk-route-source';
  static const _routeLayerId = 'walk-route-layer';
  static const _hexSourceId = 'hex-grid-source';
  static const _hexFillId = 'hex-grid-fill';
  static const _hexOutlineId = 'hex-grid-outline';

  @override
  void initState() {
    super.initState();
    _loadToken();
    _requestPermissions();
  }

  Future<void> _loadToken() async {
    final token = await AppConfig.getEffectiveMapboxToken();
    if (!mounted) return;
    setState(() => _token = token.isEmpty ? null : token);
    if (token.isNotEmpty) {
      MapboxOptions.setAccessToken(token);
    }
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.location,
      Permission.activityRecognition,
      Permission.notification,
    ].request();
  }

  // ---------- GeoJSON builders ----------

  String _routeGeoJson(TelemetryState t) {
    final coords = t.routeCoordinates
        .where((seg) => seg.length >= 2)
        .map((seg) => seg.map((p) => [p[0], p[1]]).toList())
        .toList();
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': <String, dynamic>{},
          'geometry': {
            'type': 'MultiLineString',
            'coordinates': coords,
          },
        }
      ],
    });
  }

  String _hexGeoJson(TelemetryState t) {
    final features = t.hexPolygons.map((h) {
      return {
        'type': 'Feature',
        'properties': {'hexId': h.hexId},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            h.ring.map((p) => [p[0], p[1]]).toList()
          ],
        },
      };
    }).toList();
    return jsonEncode({'type': 'FeatureCollection', 'features': features});
  }

  Future<void> _addLayers(TelemetryState t) async {
    final map = _map;
    if (map == null) return;
    try {
      await map.addSource(
        GeoJsonSource(id: _routeSourceId, data: _routeGeoJson(t)),
      );
      await map.addLayer(
        LineLayer(
          id: _routeLayerId,
          sourceId: _routeSourceId,
          lineColor: 0xFF10B981,
          lineWidth: 5.5,
          lineCap: LineCap.ROUND,
          lineJoin: LineJoin.ROUND,
        ),
      );
      await map.addSource(
        GeoJsonSource(id: _hexSourceId, data: _hexGeoJson(t)),
      );
      await map.addLayer(
        FillLayer(
          id: _hexFillId,
          sourceId: _hexSourceId,
          fillColor: 0xFF10B981,
          fillOpacity: 0.25,
        ),
      );
      await map.addLayer(
        LineLayer(
          id: _hexOutlineId,
          sourceId: _hexSourceId,
          lineColor: 0xFF047857,
          lineWidth: 2.0,
        ),
      );
      _styleReady = true;
    } catch (_) {
      // Sources may already exist after a style reload; ignore duplicates.
      _styleReady = true;
    }
  }

  Future<void> _syncLayers(TelemetryState t) async {
    final map = _map;
    if (map == null || !_styleReady) return;
    try {
      await map.updateGeoJsonSource(id: _routeSourceId, data: _routeGeoJson(t));
      await map.updateGeoJsonSource(id: _hexSourceId, data: _hexGeoJson(t));
    } catch (_) {}
    if (_follow) {
      try {
        await map.setCamera(
          CameraOptions(
            center: Point(coordinates: Position(t.longitude, t.latitude)),
            zoom: 16,
            bearing: 0,
            pitch: _pitch,
          ),
        );
      } catch (_) {}
    }
  }

  // ---------- Actions ----------

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await _requestPermissions();
      await ref.read(telemetryProvider.notifier).startWalk();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Start failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pauseResume(bool isPaused) async {
    setState(() => _busy = true);
    try {
      if (isPaused) {
        await ref.read(telemetryProvider.notifier).resumeWalk();
      } else {
        await ref.read(telemetryProvider.notifier).pauseWalk();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    try {
      final res = await ref.read(telemetryProvider.notifier).finishWalk();
      final path = (res['gpxFilePath'] ?? '').toString();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Walk saved • ${res['pointCount'] ?? 0} points'),
          action: SnackBarAction(
            label: 'View & Share GPX',
            onPressed: () {
              if (path.isNotEmpty) {
                Share.shareXFiles([XFile(path)], text: 'Terrastep GPX export');
              }
            },
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Finish failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showTokenDialog() async {
    final controller = TextEditingController(text: _token ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mapbox Token Setup'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Public token (pk.xxx)',
            hintText: 'Paste your Mapbox public token',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await ref.read(mapboxTokenProvider.notifier).save(controller.text.trim());
      await _loadToken();
      if (mounted) setState(() {});
    }
    controller.dispose();
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    final telemetry = ref.watch(telemetryProvider);
    final tokenAsync = ref.watch(mapboxTokenProvider);

    // Keep GeoJSON layers in sync with telemetry.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncLayers(telemetry));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terrastep • Live Map'),
        actions: [
          IconButton(
            tooltip: 'Mapbox token',
            icon: const Icon(Icons.key),
            onPressed: _showTokenDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map (or placeholder when token missing)
          if (_token == null || _token!.isEmpty)
            _NoTokenPlaceholder(onSetup: _showTokenDialog)
          else
            MapWidget(
              mapOptions: MapOptions(styleUri: _styleUri),
              cameraOptions: CameraOptions(
                center: Point(
                  coordinates: Position(telemetry.longitude, telemetry.latitude),
                ),
                zoom: 16,
                bearing: 0,
                pitch: _pitch,
              ),
              onMapCreated: (controller) {
                _map = controller;
              },
              onStyleLoadedListener: (controller) async {
                await _addLayers(telemetry);
              },
            ),

          // Top-right controls: follow, pitch, style
          Positioned(
            top: 12,
            right: 12,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'follow',
                  tooltip: 'Follow GPS lock',
                  onPressed: () => setState(() => _follow = !_follow),
                  child: Icon(_follow ? Icons.gps_fixed : Icons.gps_not_fixed),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'pitch',
                  tooltip: '3D pitch 0° / 45°',
                  onPressed: () {
                    setState(() => _pitch = _pitch == 0 ? 45 : 0);
                    _map?.setCamera(
                      CameraOptions(
                        center: Point(
                          coordinates: Position(telemetry.longitude, telemetry.latitude),
                        ),
                        zoom: 16,
                        bearing: 0,
                        pitch: _pitch,
                      ),
                    );
                  },
                  child: const Icon(Icons.view_in_ar),
                ),
                const SizedBox(height: 8),
                PopupMenuButton<String>(
                  tooltip: 'Map style',
                  onSelected: (uri) {
                    setState(() {
                      _styleUri = uri;
                      _styleReady = false;
                    });
                    _map?.setStyleUri(uri);
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: MapboxStyles.OUTDOORS, child: Text('Outdoors')),
                    PopupMenuItem(value: MapboxStyles.DARK, child: Text('Dark')),
                    PopupMenuItem(value: MapboxStyles.STANDARD, child: Text('Standard')),
                  ],
                  child: const FloatingActionButton.small(
                    heroTag: 'style',
                    child: Icon(Icons.layers),
                  ),
                ),
              ],
            ),
          ),

          // Bottom HUD
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _RecorderHud(
              telemetry: telemetry,
              busy: _busy,
              tokenLoading: tokenAsync.isLoading,
              onStart: _start,
              onPauseResume: _pauseResume,
              onFinish: _finish,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoTokenPlaceholder extends StatelessWidget {
  final VoidCallback onSetup;
  const _NoTokenPlaceholder({required this.onSetup});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFECFDF5),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.map, size: 64, color: Color(0xFF10B981)),
          const SizedBox(height: 16),
          const Text(
            'Mapbox token required',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add your public token (pk.xxx) to show the live map, or build with --dart-define=MAPBOX_ACCESS_TOKEN=pk.xxx',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onSetup,
            icon: const Icon(Icons.key),
            label: const Text('Set token'),
          ),
        ],
      ),
    );
  }
}

class _RecorderHud extends StatelessWidget {
  final TelemetryState telemetry;
  final bool busy;
  final bool tokenLoading;
  final VoidCallback onStart;
  final void Function(bool isPaused) onPauseResume;
  final VoidCallback onFinish;

  const _RecorderHud({
    required this.telemetry,
    required this.busy,
    required this.tokenLoading,
    required this.onStart,
    required this.onPauseResume,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final status = telemetry.status;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Stat(label: 'Steps', value: '${telemetry.steps}'),
              _Stat(label: 'Distance', value: formatDistance(telemetry.distanceMeters)),
              _Stat(label: 'Moving', value: formatMmSs(telemetry.movingDurationMs)),
              _Stat(label: 'Cadence', value: '${telemetry.cadenceSpm.toStringAsFixed(0)}/min'),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Status: $status',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Flexible(
                child: Text(
                  telemetry.currentHexId,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy || telemetry.isActive ? null : onStart,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Walk'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy || !telemetry.isActive
                      ? null
                      : () => onPauseResume(telemetry.isPaused),
                  icon: Icon(telemetry.isPaused ? Icons.play_arrow : Icons.pause),
                  label: Text(telemetry.isPaused ? 'Resume' : 'Pause'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy || !telemetry.isActive ? null : onFinish,
                  icon: const Icon(Icons.stop),
                  label: const Text('Finish & Save GPX'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF047857),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }
}
