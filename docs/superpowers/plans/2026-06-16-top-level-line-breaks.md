# Top-Level Line Breaks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make standalone `\\`, `\cr` and `\newline` render as real left-aligned line breaks in `Math.tex(...)` instead of crashing at build time.

**Architecture:** `CrNode` becomes a renderable AST node (a baseline-capable no-op) instead of a throwing `TemporaryNode`; `texBreak()` treats it as a forced break point; and `Math.build` auto-splits a top-level row at `CrNode`s into a left-aligned `Column`. Environments keep consuming `CrNode` during parsing, unchanged. Full design: `docs/superpowers/specs/2026-06-16-top-level-line-breaks-design.md`.

**Tech Stack:** Dart / Flutter, `flutter_test`. Reference: KaTeX (`KaTeX-main/src/functions/cr.ts`).

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/src/ast/nodes/cr.dart` *(new)* | `CrNode` as a renderable `LeafNode` (baseline-capable no-op). |
| `lib/src/parser/tex/functions/katex_base/cr.dart` *(modify)* | Keep `_crEntries` + `_crHandler`; construct the AST `CrNode`; drop the class definition. |
| `lib/src/parser/tex/functions/katex_base.dart` *(modify)* | Import the new node file so the handler can construct `CrNode`. |
| `lib/src/parser/tex/environments/array.dart` *(modify)* | Replace the `katex_base` import (only used for `CrNode`) with the AST node import. |
| `lib/src/parser/tex/environments/eqn_array.dart` *(modify)* | Same import swap. |
| `lib/src/ast/tex_break.dart` *(modify)* | `texBreak`: `CrNode` = forced break (-10000). New `NewlineSplitResult` + `EquationRowNode.splitAtNewlines()`. |
| `lib/src/widgets/math.dart` *(modify)* | `build`: auto-split into a left-aligned `Column`; empty segments get an explicit line height. |
| `test/cr_line_break_test.dart` *(new)* | All tests for this feature. |

---

## Task 1: Make `CrNode` a renderable AST node

**Files:**
- Create: `lib/src/ast/nodes/cr.dart`
- Modify: `lib/src/parser/tex/functions/katex_base/cr.dart`
- Modify: `lib/src/parser/tex/functions/katex_base.dart`
- Modify: `lib/src/parser/tex/environments/array.dart:35`
- Modify: `lib/src/parser/tex/environments/eqn_array.dart:38`
- Test: `test/cr_line_break_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/cr_line_break_test.dart`:

```dart
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

    test('environments with \\\\ still build', () {
      expect(r'\begin{matrix} a & b \\ c & d \end{matrix}', toBuild);
      expect(r'\begin{aligned} a &= b \\ c &= d \end{aligned}', toBuild);
      expect(r'\begin{cases} a & b \\ c & d \end{cases}', toBuild);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/cr_line_break_test.dart`
Expected: the standalone/group tests FAIL with `UnsupportedError: Temporary node CrNode encountered.` (environment tests already pass).

- [ ] **Step 3: Create the renderable `CrNode` AST node**

Create `lib/src/ast/nodes/cr.dart`:

```dart
// The MIT License (MIT)
//
// Copyright (c) 2013-2019 Khan Academy and other contributors
// Copyright (c) 2020 znjameswu <znjameswu@gmail.com>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import 'package:flutter/widgets.dart';

import '../../render/layout/reset_baseline.dart';
import '../options.dart';
import '../size.dart';
import '../syntax_tree.dart';
import '../types.dart';

/// Line break produced by `\\`, `\cr` and `\newline`.
///
/// Inside tabular/array environments this node is consumed during parsing by
/// the environment parsers (`array.dart` / `eqn_array.dart`) and never built.
/// At the top level it survives into the tree as a renderable no-op; [Math]
/// turns a top-level [CrNode] into an actual line break (see `tex_break.dart`
/// `splitAtNewlines` and `Math.build`). Mirrors KaTeX's `cr` node, whose
/// htmlBuilder emits an (empty) `mspace`.
class CrNode extends LeafNode {
  /// Whether this is a line break (`\\`, `\newline`).
  final bool newLine;

  /// Whether this is a row break (`\cr`).
  final bool newRow;

  /// Optional extra vertical spacing, e.g. `\\[1em]`.
  final Measurement? size;

  CrNode({
    required this.newLine,
    required this.newRow,
    this.size,
  });

  @override
  Mode get mode => Mode.math;

  @override
  BuildResult buildWidget(
          MathOptions options, List<BuildResult?> childBuildResults) =>
      BuildResult(
        options: options,
        // A bare SizedBox/Container reports no baseline, which crashes the line
        // layout's `getDistanceToBaseline(...)!` (line.dart:345). Wrap in
        // ResetBaseline, exactly like SpaceNode does (space.dart:82).
        widget: const ResetBaseline(height: 0, child: SizedBox.shrink()),
      );

  @override
  AtomType get leftType => AtomType.ord;

  @override
  AtomType get rightType => AtomType.ord;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      false;

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      if (newLine) 'newLine': newLine,
      if (newRow) 'newRow': newRow,
      if (size != null) 'size': size.toString(),
    });
}
```

- [ ] **Step 4: Remove the class from the parser handler and construct the AST node**

In `lib/src/parser/tex/functions/katex_base/cr.dart`, delete the `class CrNode extends TemporaryNode { ... }` block (lines 35-44). Keep `_crEntries` and `_crHandler` unchanged — `_crHandler` still ends with `return CrNode(newLine: newLine, newRow: newRow, size: size);`. The file's final content (below the license header) is:

```dart
part of katex_base;

const _crEntries = {
  ['\\cr', '\\newline']: FunctionSpec(
    numArgs: 0,
    numOptionalArgs: 1,
    allowedInText: true,
    handler: _crHandler,
  ),
};

GreenNode _crHandler(TexParser parser, FunctionContext context) {
  final size = parser.parseArgSize(optional: true);
  final newRow = context.funcName == '\\cr';
  var newLine = false;
  if (!newRow) {
    if (parser.settings.displayMode &&
        parser.settings.useStrictBehavior(
            'newLineInDisplayMode',
            'In LaTeX, \\\\ or \\newline '
                'does nothing in display mode')) {
      newLine = false;
    } else {
      newLine = true;
    }
  }
  return CrNode(newLine: newLine, newRow: newRow, size: size);
}
```

- [ ] **Step 5: Fix imports so every reference sees the moved `CrNode`**

In `lib/src/parser/tex/functions/katex_base.dart`, add this import alongside the other `../../../ast/nodes/*` imports (e.g. right after the `space.dart` import):

```dart
import '../../../ast/nodes/cr.dart';
```

In `lib/src/parser/tex/environments/array.dart`, replace line 35:

```dart
import '../functions/katex_base.dart';
```

with:

```dart
import '../../../ast/nodes/cr.dart';
```

In `lib/src/parser/tex/environments/eqn_array.dart`, replace line 38:

```dart
import '../functions/katex_base.dart';
```

with:

```dart
import '../../../ast/nodes/cr.dart';
```

(`assertNodeType`/`getHLines` come from `parser.dart` / the local `array.dart`, so the `katex_base` import was only providing `CrNode`.)

- [ ] **Step 6: Run analyzer + the tests to verify they pass**

Run: `flutter analyze lib/src/ast/nodes/cr.dart lib/src/parser/tex/functions/katex_base.dart lib/src/parser/tex/environments/array.dart lib/src/parser/tex/environments/eqn_array.dart`
Expected: no new errors. (Pre-existing warnings in unrelated files are fine.)

Run: `flutter test test/cr_line_break_test.dart`
Expected: PASS (all four groups).

- [ ] **Step 7: Run the full suite (no regression in environments)**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add lib/src/ast/nodes/cr.dart lib/src/parser/tex/functions/katex_base/cr.dart lib/src/parser/tex/functions/katex_base.dart lib/src/parser/tex/environments/array.dart lib/src/parser/tex/environments/eqn_array.dart test/cr_line_break_test.dart
git commit -m "Make CrNode a renderable AST node (no-op) instead of a TemporaryNode"
```

---

## Task 2: `texBreak()` treats `CrNode` as a forced break point

**Files:**
- Modify: `lib/src/ast/tex_break.dart` (the `EquationRowNodeTexStyleBreakExt.texBreak` loop, ~lines 43-75)
- Test: `test/cr_line_break_test.dart`

- [ ] **Step 1: Write the failing test**

Append this group to `test/cr_line_break_test.dart`, and add the import
`import 'package:flutter_math_fork/src/ast/tex_break.dart';` at the top:

```dart
  group('texBreak with CrNode', () {
    test('texBreak splits at \\\\', () {
      final result = getParsed(r'a \\ b').texBreak();
      expect(result.parts.length, 2);
    });

    test('texBreak does not split plain expression', () {
      final result = getParsed(r'a b').texBreak();
      expect(result.parts.length, 1);
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/cr_line_break_test.dart --plain-name 'texBreak splits'`
Expected: FAIL — `Expected: 2, Actual: 1` (CrNode not yet a break point).

- [ ] **Step 3: Add the `CrNode` branch to the texBreak loop**

In `lib/src/ast/tex_break.dart`, add the import at the top (next to `import 'nodes/space.dart';`):

```dart
import 'nodes/cr.dart';
```

In `EquationRowNodeTexStyleBreakExt.texBreak`, extend the per-child decision chain. Change this block (≈ lines 65-74):

```dart
      if (child.rightType == AtomType.bin) {
        breakIndices.add(i);
        penalties.add(binOpPenalty);
      } else if (child.rightType == AtomType.rel) {
        breakIndices.add(i);
        penalties.add(relPenalty);
      } else if (child is SpaceNode && child.breakPenalty != null) {
        breakIndices.add(i);
        penalties.add(child.breakPenalty!);
      }
```

to:

```dart
      if (child is CrNode) {
        // Manual line break (\\, \cr, \newline): a mandatory break.
        breakIndices.add(i);
        penalties.add(-10000);
      } else if (child.rightType == AtomType.bin) {
        breakIndices.add(i);
        penalties.add(binOpPenalty);
      } else if (child.rightType == AtomType.rel) {
        breakIndices.add(i);
        penalties.add(relPenalty);
      } else if (child is SpaceNode && child.breakPenalty != null) {
        breakIndices.add(i);
        penalties.add(child.breakPenalty!);
      }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/cr_line_break_test.dart --plain-name 'texBreak'`
Expected: PASS (both texBreak tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/ast/tex_break.dart test/cr_line_break_test.dart
git commit -m "Treat CrNode as a forced break point in texBreak"
```

---

## Task 3: `splitAtNewlines()` on `EquationRowNode`

**Files:**
- Modify: `lib/src/ast/tex_break.dart` (add `NewlineSplitResult` + extension method)
- Test: `test/cr_line_break_test.dart`

- [ ] **Step 1: Write the failing tests**

Append this group to `test/cr_line_break_test.dart`:

```dart
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
      expect(r.gaps[0], isNot(equals(Measurement.zero)));
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/cr_line_break_test.dart --plain-name 'splitAtNewlines'`
Expected: FAIL to compile — `The method 'splitAtNewlines' isn't defined`.

- [ ] **Step 3: Implement `NewlineSplitResult` and `splitAtNewlines()`**

In `lib/src/ast/tex_break.dart`, add the size import at the top (next to the existing `import 'syntax_tree.dart';`):

```dart
import 'size.dart';
```

Then append at the end of the file:

```dart
/// Result of splitting an [EquationRowNode] at its top-level [CrNode]s.
class NewlineSplitResult {
  /// One [EquationRowNode] per line (without the separating [CrNode]s).
  final List<EquationRowNode> lines;

  /// Extra vertical gap after each line, taken from the separating `\\[size]`.
  ///
  /// `gaps[i]` is the gap between `lines[i]` and `lines[i + 1]`; length is
  /// `lines.length - 1` (or less if a trailing empty line was dropped).
  final List<Measurement> gaps;

  const NewlineSplitResult({required this.lines, required this.gaps});
}

extension EquationRowNodeNewlineSplitExt on EquationRowNode {
  /// Splits this row into separate lines at every top-level [CrNode].
  ///
  /// The `CrNode`s themselves are removed (they are separators, not content).
  /// A single trailing empty line (from a trailing `\\`) is dropped; leading
  /// and inner empty lines are kept as real blank lines.
  NewlineSplitResult splitAtNewlines() {
    final flattened = flattenedChildList;
    final crIndices = <int>[];
    for (var i = 0; i < flattened.length; i++) {
      if (flattened[i] is CrNode) {
        crIndices.add(i);
      }
    }
    if (crIndices.isEmpty) {
      return NewlineSplitResult(lines: [this], gaps: const []);
    }

    final lines = <EquationRowNode>[];
    final gaps = <Measurement>[];
    var pos = caretPositions.first;
    for (final k in crIndices) {
      // Clip up to the caret position *before* the CrNode, excluding it.
      lines.add(clipChildrenBetween(pos, caretPositions[k]).wrapWithEquationRow());
      gaps.add((flattened[k] as CrNode).size ?? Measurement.zero);
      // Resume *after* the CrNode.
      pos = caretPositions[k + 1];
    }
    final trailing =
        clipChildrenBetween(pos, caretPositions.last).wrapWithEquationRow();
    if (trailing.children.isNotEmpty) {
      lines.add(trailing);
    } else {
      // Drop a single trailing empty line and its preceding gap.
      if (gaps.isNotEmpty) gaps.removeLast();
    }

    return NewlineSplitResult(lines: lines, gaps: gaps);
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/cr_line_break_test.dart --plain-name 'splitAtNewlines'`
Expected: PASS (all six cases).

- [ ] **Step 5: Commit**

```bash
git add lib/src/ast/tex_break.dart test/cr_line_break_test.dart
git commit -m "Add EquationRowNode.splitAtNewlines() for top-level line breaks"
```

---

## Task 4: `Math.build` auto-splits into a left-aligned Column

**Files:**
- Modify: `lib/src/widgets/math.dart` (imports + `build`, ~lines 198-213)
- Test: `test/cr_line_break_test.dart`

- [ ] **Step 1: Write the failing tests**

Append this group to `test/cr_line_break_test.dart` (uses `dart:ui`-free APIs only):

```dart
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/cr_line_break_test.dart --plain-name 'auto-split'`
Expected: FAIL — no `Column` is produced (and the height test fails because `a \\\\ b` currently throws / has no extra line).

- [ ] **Step 3: Add the import and the auto-split in `Math.build`**

In `lib/src/widgets/math.dart`, add after the existing `import '../ast/syntax_tree.dart';` (line 6):

```dart
import '../ast/nodes/cr.dart';
```

Replace the build block (the `Widget child; try { child = ast!.buildWidget(options); } ...`, lines 198-208) with:

```dart
    Widget child;

    try {
      final row = ast!.greenRoot;
      if (row.flattenedChildList.any((node) => node is CrNode)) {
        // Top-level manual line breaks: lay the lines out vertically,
        // left-aligned (see design doc + KaTeX cr.ts).
        final split = row.splitAtNewlines();
        final columnChildren = <Widget>[];
        for (var i = 0; i < split.lines.length; i++) {
          final line = split.lines[i];
          columnChildren.add(
            line.children.isEmpty
                // An empty Line collapses to height 0 (line.dart:96). Give a
                // blank line one line's height; options.fontSize is the
                // package's preferred line height (selectable.dart:553).
                ? SizedBox(height: options.fontSize)
                : SyntaxTree(greenRoot: line).buildWidget(options),
          );
          if (i < split.gaps.length) {
            final gap = split.gaps[i].toLpUnder(options);
            if (gap > 0) {
              columnChildren.add(SizedBox(height: gap));
            }
          }
        }
        child = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: columnChildren,
        );
      } else {
        child = ast!.buildWidget(options);
      }
    } on BuildException catch (e) {
      return onErrorFallback(e);
    } on Object catch (e) {
      return onErrorFallback(
          BuildException('Unsanitized build exception detected: $e.'
              'Please report this error with correponding input.'));
    }
```

(`Measurement.toLpUnder` is already on the `Measurement` returned by `split.gaps`; `size.dart` is reachable transitively through `tex_break.dart`. If the analyzer reports `toLpUnder`/`Measurement` as undefined, add `import '../ast/size.dart';`.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/cr_line_break_test.dart --plain-name 'auto-split'`
Expected: PASS (all three widget tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/widgets/math.dart test/cr_line_break_test.dart
git commit -m "Auto-split Math into a left-aligned Column at top-level line breaks"
```

---

## Task 5: Full regression + analyzer

**Files:** none (verification only)

- [ ] **Step 1: Run the whole test suite**

Run: `flutter test`
Expected: all tests pass (the existing 405 + the new `cr_line_break_test.dart` tests).

- [ ] **Step 2: Run the analyzer over the touched files**

Run: `flutter analyze lib/src/ast lib/src/parser/tex/environments lib/src/parser/tex/functions/katex_base.dart lib/src/widgets/math.dart`
Expected: no new errors or warnings introduced by this change (the two pre-existing `overlay.dart` findings are unrelated and out of scope).

- [ ] **Step 3: Commit (only if anything changed)**

```bash
git add -A
git commit -m "Tidy up after top-level line break feature" || echo "nothing to commit"
```

---

## Notes for the implementer

- **Do not touch the parser's split decision.** `TexParser.parse()` stays unchanged; `CrNode`s remain in the top-level row and are only interpreted at widget-build time.
- **Environments are unchanged in behaviour.** They consume `CrNode` during parsing (`assertNodeType<CrNode>`); the only change there is the import path.
- **`SelectableMath` is intentionally out of scope** — it keeps its single-line build path; a top-level `CrNode` there renders as the no-op box (no crash), and multi-line is available via `Math.texBreak()`.
- **Deliberate KaTeX divergences** (documented in the spec §7): top-level `\cr` renders here (KaTeX errors); `displayMode + strict` still breaks here.
