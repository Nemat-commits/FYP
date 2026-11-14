import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/walk_providers.dart';

/// Native diagnostics: step sensors, baseline, last GPS fix (Blueprint 30% scope).
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagAsync = ref.watch(diagnosticsProvider);
    final telemetry = ref.watch(telemetryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(diagnosticsProvider.notifier).refresh(),
          ),
        ],
      ),
      body: diagAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Diagnostics unavailable:\n$e')),
        data: (d) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _DiagCard(
              title: 'Hardware step sensors',
              rows: {
                'TYPE_STEP_COUNTER': _bool(d['hasStepCounter']),
                'TYPE_STEP_DETECTOR': _bool(d['hasStepDetector']),
                'Any step sensor': _bool(telemetry.hasStepSensor),
              },
            ),
            const SizedBox(height: 12),
            _DiagCard(
              title: 'Session counters',
              rows: {
                'Status': (d['status'] ?? telemetry.status).toString(),
                'Session steps': (d['sessionSteps'] ?? telemetry.steps).toString(),
                'Raw boot steps': (d['rawBootSteps'] ?? telemetry.rawBootSteps).toString(),
                'Baseline at start': (d['sessionBaselineSteps'] ?? '—').toString(),
                'Cadence': '${telemetry.cadenceSpm.toStringAsFixed(1)} spm',
              },
            ),
            const SizedBox(height: 12),
            _DiagCard(
              title: 'Last GPS fix',
              rows: {
                'Latitude': _fmt(d['lastLat'] ?? telemetry.latitude),
                'Longitude': _fmt(d['lastLon'] ?? telemetry.longitude),
                'Accuracy': '${_fmt(d['lastAccuracyMeters'] ?? telemetry.accuracyMeters)} m',
                'Current hex': telemetry.currentHexId,
                'Visited hex cells': '${telemetry.visitedHexCount}',
              },
            ),
            const SizedBox(height: 12),
            _DiagCard(
              title: 'Pilot origin',
              rows: const {
                'Abbottabad': '34.1688° N, 73.2215° E',
                'Hex engine': 'Resolution-9 (~195 m radius)',
                'Accuracy gate': '≤ 25 m',
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'If step sensors show “No”, test on a physical ARM64 device (e.g. Galaxy S23). '
              'Emulators without step sensors fall back to the demo walk generator in GPX History.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  static String _bool(dynamic v) => (v == true) ? 'Yes' : 'No';

  static String _fmt(dynamic v) {
    if (v == null) return '—';
    if (v is num) return v.toStringAsFixed(6);
    return v.toString();
  }
}

class _DiagCard extends StatelessWidget {
  final String title;
  final Map<String, String> rows;
  const _DiagCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final e in rows.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(e.key, style: const TextStyle(color: Colors.black54)),
                    Flexible(
                      child: Text(
                        e.value,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
