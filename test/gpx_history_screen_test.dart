import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrastep/ui/screens/gpx_history_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.terrastep.fyp/methods');
  late List<Map<String, dynamic>> sessions;

  setUp(() {
    sessions = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getSavedSessions': return sessions;
        case 'getSessionDetail': return {'gpxXml': '<gpx version="1.1"></gpx>', 'gpxFilePath': '/walk.gpx'};
        default: fail('Unexpected bridge method: ${call.method}');
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('empty history has no demo generator', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GpxHistoryScreen()));
    await tester.pumpAndSettle();
    expect(find.text('No saved walks yet. Finish a walk to save its GPX file.'), findsOneWidget);
    expect(find.textContaining('Generate'), findsNothing);
    expect(find.byIcon(Icons.auto_fix_high), findsNothing);
  });

  testWidgets('saved walks and GPX inspection still work', (tester) async {
    sessions = [{'sessionId': 'one', 'title': 'My walk', 'totalSteps': 120, 'totalDistanceMeters': 100.0, 'gpxFilePath': '/walk.gpx'}];
    await tester.pumpWidget(const MaterialApp(home: GpxHistoryScreen()));
    await tester.pumpAndSettle();
    expect(find.text('My walk'), findsOneWidget);
    expect(find.text('120 steps • 0.10 km'), findsOneWidget);
    await tester.tap(find.text('Inspect GPX XML'));
    await tester.pumpAndSettle();
    expect(find.text('<gpx version="1.1"></gpx>'), findsOneWidget);
    expect(find.byTooltip('Copy Raw GPX XML'), findsOneWidget);
  });
}
