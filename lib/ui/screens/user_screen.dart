import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/native_tracker_bridge.dart';

class UserScreen extends StatefulWidget {
  const UserScreen({super.key, required this.active});
  final bool active;

  @override
  State<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  String _name = 'Walker';
  double _distance = 0;
  List<List<Offset>> _paths = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant UserScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessions = await NativeTrackerBridge.getSavedSessions();
      final paths = <List<Offset>>[];
      double distance = 0;
      for (final session in sessions) {
        // Demo fixtures must not count as the user's walking history.
        if ((session['title'] ?? '').toString().startsWith('Abbottabad Pilot Trail')) continue;
        if (session['status'] != 'COMPLETED') continue;
        distance += (session['totalDistanceMeters'] as num?)?.toDouble() ?? 0;
        final detail = await NativeTrackerBridge.getSessionDetail(session['sessionId'] as String);
        final segments = <int, List<Offset>>{};
        for (final raw in (detail['points'] as List? ?? [])) {
          final point = Map<String, dynamic>.from(raw as Map);
          final index = (point['segmentIndex'] as num).toInt();
          (segments[index] ??= []).add(Offset(
            (point['lon'] as num).toDouble(), (point['lat'] as num).toDouble(),
          ));
        }
        paths.addAll(segments.values.where((segment) => segment.length >= 2));
      }
      if (!mounted) return;
      setState(() {
        _name = prefs.getString('user_name') ?? 'Walker';
        _distance = distance;
        _paths = paths;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Could not load your path. Pull down to retry.';
      });
    }
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller, autofocus: true, maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    if (name == null || name.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name);
    if (mounted) setState(() => _name = name);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('User')),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Card(child: ListTile(
            title: Text(_name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            trailing: IconButton(tooltip: 'Edit name', icon: const Icon(Icons.edit_outlined), onPressed: _editName),
          )),
          const SizedBox(height: 16),
          Card(child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Path covered', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (_loading) const Center(child: CircularProgressIndicator())
              else if (_error != null) Text(_error!)
              else ...[
                Text('${(_distance / 1000).toStringAsFixed(2)} km', style: const TextStyle(fontSize: 30, color: Color(0xFF34D399))),
                const SizedBox(height: 16),
                if (_paths.isEmpty) const Text('Your saved walking paths will appear here.')
                else SizedBox(height: 240, width: double.infinity, child: CustomPaint(painter: _PathPainter(_paths))),
              ],
            ]),
          )),
        ],
      ),
    ),
  );
}

/// A local route overview, with pause segments kept separate. No network map required.
class _PathPainter extends CustomPainter {
  _PathPainter(this.paths);
  final List<List<Offset>> paths;

  @override
  void paint(Canvas canvas, Size size) {
    final points = paths.expand((path) => path).toList();
    if (points.isEmpty) return;
    final lat = points.map((p) => p.dy).reduce((a, b) => a + b) / points.length;
    final scale = math.cos(lat * math.pi / 180);
    final projected = paths.map((path) => path.map((p) => Offset(p.dx * scale, -p.dy)).toList()).toList();
    final all = projected.expand((p) => p).toList();
    final left = all.map((p) => p.dx).reduce(math.min);
    final right = all.map((p) => p.dx).reduce(math.max);
    final top = all.map((p) => p.dy).reduce(math.min);
    final bottom = all.map((p) => p.dy).reduce(math.max);
    final factor = math.min((size.width - 24) / math.max(right - left, 0.000001), (size.height - 24) / math.max(bottom - top, 0.000001));
    final center = Offset((left + right) / 2, (top + bottom) / 2);
    final paint = Paint()..color = const Color(0xFF34D399)..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    for (final segment in projected) {
      final path = Path();
      for (var i = 0; i < segment.length; i++) {
        final p = (segment[i] - center) * factor + size.center(Offset.zero);
        if (i == 0) { path.moveTo(p.dx, p.dy); } else { path.lineTo(p.dx, p.dy); }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PathPainter oldDelegate) => oldDelegate.paths != paths;
}
