import 'package:flutter/material.dart';
import 'package:flutter_math_fork/ast.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helper.dart';

void main() {
  group('CrNode renderability', () {
    test('standalone \\\\ builds without crashing', () {
      expect(r'a \\ b', toBuild);
    });

    test('standalone \\cr and \\newline build', () {
      expect(r'a \cr b', toBuild);
      expect(r'a \newline b', toBuild);
    });

    test('\\\\ inside a group builds (baseline path)', () {
      // The CrNode is built inside a Line here, so it must report a baseline.
      expect(r'{a \\ b}', toBuild);
    });

    testWidgets('SelectableMath with \\\\ builds (single-line, no crash)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Center(child: SelectableMath.tex(r'a \\ b'))),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    test('environments with \\\\ still build', () {
      expect(r'\begin{matrix} a & b \\ c & d \end{matrix}', toBuild);
      expect(r'\begin{aligned} a &= b \\ c &= d \end{aligned}', toBuild);
      expect(r'\begin{cases} a & b \\ c & d \end{cases}', toBuild);
    });
  });

  group('texBreak with CrNode', () {
    test('texBreak splits at \\\\', () {
      final result = getParsed(r'a \\ b').texBreak();
      expect(result.parts.length, 2);
      expect(result.penalties.first, -10000); // mandatory break sentinel
    });

    test('texBreak splits at \\cr', () {
      final result = getParsed(r'a \cr b').texBreak();
      expect(result.parts.length, 2);
    });

    test('texBreak does not split plain expression', () {
      final result = getParsed(r'a b').texBreak();
      expect(result.parts.length, 1);
    });
  });

  group('splitAtNewlines', () {
    test('a \\\\ b -> 2 non-empty lines', () {
      final r = getParsed(r'a \\ b').splitAtNewlines();
      expect(r.lines.length, 2);
      expect(r.lines[0].children, isNotEmpty);
      expect(r.lines[1].children, isNotEmpty);
      expect(r.gaps.length, 1);
    });

    test('trailing \\\\ drops the empty last line', () {
      final r = getParsed(r'a \\ b \\').splitAtNewlines();
      expect(r.lines.length, 2);
      expect(r.gaps.length, 1);
    });

    test('leading \\\\ keeps the empty first line', () {
      final r = getParsed(r'\\ a').splitAtNewlines();
      expect(r.lines.length, 2);
      expect(r.lines[0].children, isEmpty);
      expect(r.lines[1].children, isNotEmpty);
    });

    test('a \\\\\\\\ b keeps the empty middle line', () {
      final r = getParsed(r'a \\\\ b').splitAtNewlines();
      expect(r.lines.length, 3);
      expect(r.lines[1].children, isEmpty);
    });

    test('expression without \\\\ yields a single line', () {
      final r = getParsed(r'a + b').splitAtNewlines();
      expect(r.lines.length, 1);
      expect(r.gaps, isEmpty);
    });

    test('\\\\[1em] records a non-zero gap', () {
      final r = getParsed(r'a \\[1em] b').splitAtNewlines();
      expect(r.lines.length, 2);
      expect(r.gaps.length, 1);
      expect(r.gaps[0].value, 1);
      expect(r.gaps[0].unit, Unit.em);
    });

    test('lone \\\\ yields one empty line and no gaps', () {
      final r = getParsed(r'\\').splitAtNewlines();
      expect(r.lines.length, 1);
      expect(r.lines[0].children, isEmpty);
      expect(r.gaps, isEmpty);
    });
  });

  group('Math auto-split rendering', () {
    testWidgets('\\\\ renders as a left-aligned Column', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Center(child: Math.tex(r'a \\ b'))),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Column), findsOneWidget);
      final column = tester.widget<Column>(find.byType(Column));
      expect(column.crossAxisAlignment, CrossAxisAlignment.start);
    });

    testWidgets('expression without \\\\ does not produce a Column',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Center(child: Math.tex(r'a + b'))),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Column), findsNothing);
    });

    testWidgets(r'\\[1em] gap adds rendered height', (tester) async {
      Future<double> heightOf(String tex) async {
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(home: Center(child: Math.tex(tex, key: key))),
        );
        await tester.pumpAndSettle();
        return tester.getSize(find.byKey(key)).height;
      }

      final noGap = await heightOf(r'a \\ b');
      final withGap = await heightOf(r'a \\[1em] b');
      expect(withGap, greaterThan(noGap));
    });

    testWidgets('\\newline also renders as a Column', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Center(child: Math.tex(r'a \newline b'))),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Column), findsOneWidget);
    });

    testWidgets('empty middle line keeps real height', (tester) async {
      Future<double> heightOf(String tex) async {
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(home: Center(child: Math.tex(tex, key: key))),
        );
        await tester.pumpAndSettle();
        return tester.getSize(find.byKey(key)).height;
      }

      final twoLines = await heightOf(r'a \\ b');
      final withEmptyMiddle = await heightOf(r'a \\\\ b');
      // The extra (empty) middle line must add height, not collapse to 0.
      expect(withEmptyMiddle, greaterThan(twoLines));
    });
  });
}
