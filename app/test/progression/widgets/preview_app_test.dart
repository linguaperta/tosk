import 'package:tosk/main_progression_preview.dart';
import 'package:tosk/ui/progression/progression_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(1200, 900), const Size(390, 844)]) {
    testWidgets('preview app renders every section without layout errors at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ProgressionPreviewApp());
      await tester.pumpAndSettle();
      expect(find.byType(LevelBadge), findsWidgets);
      expect(find.byType(StreakHeatmap), findsOneWidget);

      // Toggle reduce motion and dark mode.
      await tester.tap(find.byType(Switch).last);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      // Scroll through the page and drive the HUD.
      await tester.scrollUntilVisible(find.text('Correct'), 300, scrollable: find.byType(Scrollable).first);
      for (var i = 0; i < 26; i++) {
        await tester.tap(find.text('Correct'));
        await tester.pump();
      }
      expect(find.byKey(const ValueKey('bonus-banner')), findsOneWidget);
      await tester.tap(find.text('Wrong'));
      await tester.pump();
      expect(find.text('Combo 0'), findsOneWidget);
      await tester.scrollUntilVisible(find.byType(VerbCollectionView), 300, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
