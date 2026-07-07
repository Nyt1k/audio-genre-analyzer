import 'package:flutter_test/flutter_test.dart';

import 'package:genre_analyzer/main.dart';

void main() {
  testWidgets('app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const GenreApp());
    expect(find.text('START'), findsOneWidget);
    expect(find.text('GENRE ANALYZER'), findsOneWidget);
  });
}
