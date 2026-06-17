import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

Future<double> heightOf(WidgetTester tester, Widget w, double width) async {
  final key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: KeyedSubtree(key: key, child: w)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return tester.getSize(find.byKey(key)).height;
}

void main() {
  testWidgets('soft-wraps a long line in a narrow box', (tester) async {
    const expr = r'a + b + c + d + e + f + g + h + i + j';
    final wide = await heightOf(tester, MathFit.tex(expr), 1000);
    final narrow = await heightOf(tester, MathFit.tex(expr), 80);
    expect(narrow, greaterThan(wide));
  });

  testWidgets('honors a manual \\\\ break', (tester) async {
    final single = await heightOf(tester, Math.tex(r'x = a'), 1000);
    final twoLines =
        await heightOf(tester, MathFit.tex(r'x = a \\ y = b'), 1000);
    expect(twoLines, greaterThan(single * 1.5));
  });

  testWidgets('an unbreakable too-wide line scrolls horizontally',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 80,
            // A single fraction is one unbreakable part, far wider than 80px.
            child: MathFit.tex(r'\frac{a + b + c + d + e + f + g + h}{2}'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final state = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(state.position.maxScrollExtent, greaterThan(0));
  });

  testWidgets('a line that fits does not scroll', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 1000, child: MathFit.tex(r'a + b')),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final state = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(state.position.maxScrollExtent, 0);
  });

  testWidgets('builds a plain expression without error', (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: Center(child: MathFit.tex(r'a + b'))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
