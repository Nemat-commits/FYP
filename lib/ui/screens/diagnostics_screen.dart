import 'package:flutter/material.dart';
import '../../core/app_config.dart';
import '../../services/native_tracker_bridge.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  Map<String, dynamic> _diag = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await NativeTrackerBridge.getDiagnostics();
    if (!mounted) return;
    setState(() => _diag = d);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('30% FYP Verification Checklist'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.directions_walk, color: Color(0xFF10B981)),
              title: const Text('1. Hardware Step Counter Sensor'),
              subtitle: Text(
                'TYPE_STEP_COUNTER: ${_diag['hasStepCounter'] ?? false}\n'
                'Raw Boot Steps: ${_diag['rawBootSteps'] ?? 0}\n'
                'Session Baseline: ${_diag['sessionBaselineSteps'] ?? 'Not started'}\n'
                'Current Session Steps: ${_diag['sessionSteps'] ?? 0}',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.map, color: Color(0xFF10B981)),
              title: const Text('2. Full Mapbox API Implementation'),
              subtitle: Text(
                'SDK: mapbox_maps_flutter v2.8.0 (Mapbox v11)\n'
                'Token Configured: ${AppConfig.mapboxPublicToken.startsWith('pk.') ? 'Yes (pk.eyJ1...)' : 'No'}\n'
                'Last Fix: ${_diag['lastLat'] ?? AppConfig.abbottabadLat}, ${_diag['lastLon'] ?? AppConfig.abbottabadLon}\n'
                'Horizontal Accuracy: ${_diag['lastAccuracyMeters'] ?? 0.0} m',
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.insert_drive_file, color: Color(0xFF10B981)),
              title: Text('3. Local GPX 1.1 XML Creation'),
              subtitle: Text(
                'Storage: Android Room + XmlSerializer\n'
                'Schema: GPX 1.1 (<metadata>, <wpt>, <trk>, <trkseg>, <trkpt>)\n'
                'Export: In-App XML Inspector + Public Downloads/Terrastep/ + OS Share',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
