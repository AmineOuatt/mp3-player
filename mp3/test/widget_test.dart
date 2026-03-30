// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:mp3/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    await binding.setSurfaceSize(const Size(1200, 2000));

    // Build our app and trigger a frame.
    await tester.pumpWidget(const AudioRepeaterApp());
    await tester.pumpAndSettle();

    // Verify that the title is in the app bar.
    expect(find.text('No Audio Loaded'), findsOneWidget);

    await binding.setSurfaceSize(null);
  });
}
