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
  testWidgets('honors manual \\\\ even in a wide box', (tester) async {
    final single = await heightOf(tester, Math.tex(r'x = a + b'), 1000);
    final wrapped =
        await heightOf(tester, MathWrap.tex(r'x = a + b \\ y = c + d'), 1000);
    // \\ forces 2 lines even though everything fits on one line in a wide box.
    expect(wrapped, greaterThan(single * 1.5));
  });

  testWidgets('soft-wraps a long expression in a narrow box', (tester) async {
    const expr = r'a + b + c + d + e + f + g + h + i + j';
    final wide = await heightOf(tester, MathWrap.tex(expr), 1000);
    final narrow = await heightOf(tester, MathWrap.tex(expr), 80);
    // No \\, but a narrow box must wrap at the +-operators -> taller.
    expect(narrow, greaterThan(wide));
  });

  testWidgets('builds a plain expression without error', (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: Center(child: MathWrap.tex(r'a + b'))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('shrink-wraps to content width even with a manual break',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          // MathWrap is placed directly under a loose-constraint Align so the
          // Column it builds can report its natural (content) width.  With a
          // manual \\, each line has a single short symbol, so the widget must
          // be far narrower than the 800 px test viewport.
          child: MathWrap.tex(r'a \\ b', key: key),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // With a manual break, the block must size to its content (one short
    // symbol per line), NOT stretch to the full available width.
    expect(tester.getSize(find.byKey(key)).width, lessThan(100));
  });

  testWidgets('memoizes the break result across rebuilds with same expression',
      (tester) async {
    MathWrap.debugRecomputeCount = 0;
    final notifier = ValueNotifier<int>(0);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: notifier,
          builder: (_, __, ___) => MathWrap.tex(r'a + b \\ c + d'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(MathWrap.debugRecomputeCount, 1);

    notifier.value = 1; // forces a rebuild of MathWrap with the same expression
    await tester.pumpAndSettle();
    expect(MathWrap.debugRecomputeCount, 1); // not recomputed
  });

  testWidgets('recomputes when the expression changes', (tester) async {
    MathWrap.debugRecomputeCount = 0;
    final expr = ValueNotifier<String>(r'a + b');
    addTearDown(expr.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<String>(
          valueListenable: expr,
          builder: (_, value, __) => MathWrap.tex(value),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(MathWrap.debugRecomputeCount, 1);

    expr.value = r'c + d';
    await tester.pumpAndSettle();
    expect(MathWrap.debugRecomputeCount, 2); // recomputed for the new expression
  });
}
