import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:terrastep/ui/screens/user_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.terrastep.fyp/methods');

  setUp(() {
    SharedPreferences.setMockInitialValues({'user_name': 'Nemat'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getSavedSessions') return [
        {'sessionId': 'real', 'title': 'Walk', 'status': 'COMPLETED', 'totalDistanceMeters': 1250.0},
        {'sessionId': 'demo', 'title': 'Abbottabad Pilot Trail (Demo)', 'status': 'COMPLETED', 'totalDistanceMeters': 9999.0},
      ];
      if (call.method == 'getSessionDetail') return {'points': [
        {'lon': 73.2215, 'lat': 34.1688, 'segmentIndex': 0},
        {'lon': 73.2225, 'lat': 34.1698, 'segmentIndex': 0},
      ]};
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('shows name and saved path distance without counting demo walks', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: UserScreen(active: true)));
    await tester.pumpAndSettle();
    expect(find.text('Nemat'), findsOneWidget);
    expect(find.text('Path covered'), findsOneWidget);
    expect(find.text('1.25 km'), findsOneWidget);
    expect(find.text('30% Check'), findsNothing);
  });

  testWidgets('edited name persists locally', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: UserScreen(active: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Walker Two  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Walker Two'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('user_name'), 'Walker Two');
  });

  testWidgets('empty name does not overwrite saved name', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: UserScreen(active: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect((await SharedPreferences.getInstance()).getString('user_name'), 'Nemat');
  });
}
