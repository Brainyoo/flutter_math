import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The child is 200x100. ScaleDownToFit's rendered height == 100 * scale,
  // so height is a clean probe for the applied scale.
  Future<double> heightFor(
      WidgetTester tester, double boxWidth, double minScale) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: boxWidth,
            child: ScaleDownToFit(
              key: key,
              minScale: minScale,
              child: const SizedBox(width: 200, height: 100),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return tester.getSize(find.byKey(key)).height;
  }

  testWidgets('keeps natural size when it already fits', (tester) async {
    expect(await heightFor(tester, 250, 0.6), moreOrLessEquals(100, epsilon: 0.5));
  });

  testWidgets('scales down to fit when wider than the box', (tester) async {
    // 200 in 150 -> scale 0.75 -> height 75
    expect(await heightFor(tester, 150, 0.6), moreOrLessEquals(75, epsilon: 0.5));
  });

  testWidgets('does not shrink below minScale', (tester) async {
    // 200 in 100 -> raw 0.5 floored to 0.6 -> height 60
    expect(await heightFor(tester, 100, 0.6), moreOrLessEquals(60, epsilon: 0.5));
  });

  testWidgets('below the floor the content scrolls horizontally',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 100,
            child: ScaleDownToFit(
              minScale: 0.6,
              child: const SizedBox(width: 300, height: 50),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // 300 floored at 0.6 -> 180 wide > 100 viewport -> scrollable.
    final state = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(state.position.maxScrollExtent, greaterThan(0));
  });
}
