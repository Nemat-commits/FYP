import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/native_tracker_bridge.dart';

class GpxHistoryScreen extends StatefulWidget {
  const GpxHistoryScreen({super.key});

  @override
  State<GpxHistoryScreen> createState() => _GpxHistoryScreenState();
}

class _GpxHistoryScreenState extends State<GpxHistoryScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final list = await NativeTrackerBridge.getSavedSessions();
    if (!mounted) return;
    setState(() {
      _sessions = list;
      _loading = false;
    });
  }

  Future<void> _inspectGpx(String sessionId, String title) async {
    final detail = await NativeTrackerBridge.getSessionDetail(sessionId);
    if (!mounted) return;
    final xml = (detail['gpxXml'] as String?) ?? '';
    final path = (detail['gpxFilePath'] as String?) ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        builder: (_, controller) => Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy Raw GPX XML',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: xml));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied GPX 1.1 XML to clipboard')),
                      );
                    },
                  ),
                ],
              ),
              Text(
                'File: $path',
                style: const TextStyle(fontSize: 11, color: Colors.white60),
              ),
              const Divider(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  child: SelectableText(
                    xml,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local GPX 1.1 Files & History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await NativeTrackerBridge.generateDemoWalk();
                  await _refresh();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Generated Abbottabad Demo Walk GPX 1.1 file')),
                  );
                },
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Generate Abbottabad Demo Walk (.gpx Fixture)'),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _sessions.isEmpty
                    ? const Center(
                        child: Text('No saved walks yet. Start a walk or generate a demo GPX.'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _sessions.length,
                        itemBuilder: (ctx, idx) {
                          final s = _sessions[idx];
                          final sessionId = s['sessionId'] as String;
                          final title = (s['title'] as String?) ?? 'Walk';
                          final steps = (s['totalSteps'] as num?)?.toInt() ?? 0;
                          final distM = (s['totalDistanceMeters'] as num?)?.toDouble() ?? 0.0;
                          final gpxPath = (s['gpxFilePath'] as String?) ?? '';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(14.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '$steps steps • ${(distM / 1000.0).toStringAsFixed(2)} km',
                                    style: const TextStyle(color: Color(0xFF34D399)),
                                  ),
                                  if (gpxPath.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      gpxPath,
                                      style: const TextStyle(fontSize: 11, color: Colors.white54),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      FilledButton.tonalIcon(
                                        onPressed: () => _inspectGpx(sessionId, title),
                                        icon: const Icon(Icons.code, size: 18),
                                        label: const Text('Inspect GPX XML'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () async {
                                          final saved = await NativeTrackerBridge.exportToDownloads(sessionId);
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Saved to $saved')),
                                          );
                                        },
                                        icon: const Icon(Icons.download, size: 18),
                                        label: const Text('Save to Downloads'),
                                      ),
                                      if (gpxPath.isNotEmpty)
                                        OutlinedButton.icon(
                                          onPressed: () => Share.shareXFiles([XFile(gpxPath)]),
                                          icon: const Icon(Icons.share, size: 18),
                                          label: const Text('Share .gpx'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
