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
      double distance = 0;
      for (final session in sessions) {
        // Demo fixtures must not count as the user's walking history.
        if ((session['title'] ?? '').toString().startsWith('Abbottabad Pilot Trail')) continue;
        if (session['status'] != 'COMPLETED') continue;
        distance += (session['totalDistanceMeters'] as num?)?.toDouble() ?? 0;
      }
      if (!mounted) return;
      setState(() {
        _name = prefs.getString('user_name') ?? 'Walker';
        _distance = distance;
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
              ],
            ]),
          )),
        ],
      ),
    ),
  );
}
