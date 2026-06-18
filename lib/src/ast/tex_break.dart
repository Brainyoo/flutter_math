import 'nodes/cr.dart';
import 'nodes/space.dart';

import 'size.dart';
import 'syntax_tree.dart';

extension SyntaxTreeTexStyleBreakExt on SyntaxTree {
  /// Line breaking results using standard TeX-style line breaking.
  ///
  /// This function will return a list of `SyntaxTree` along with a list
  /// of line breaking penalties.
  ///
  /// {@macro flutter_math_fork.widgets.math.tex_break}
  BreakResult<SyntaxTree> texBreak({
    int relPenalty = 500,
    int binOpPenalty = 700,
    bool enforceNoBreak = true,
  }) {
    final eqRowBreakResult = greenRoot.texBreak(
      relPenalty: relPenalty,
      binOpPenalty: binOpPenalty,
      enforceNoBreak: true,
    );
    return BreakResult(
      parts: eqRowBreakResult.parts
          .map((part) => SyntaxTree(greenRoot: part))
          .toList(growable: false),
      penalties: eqRowBreakResult.penalties,
    );
  }
}

extension EquationRowNodeTexStyleBreakExt on EquationRowNode {
  /// Line breaking results using standard TeX-style line breaking.
  ///
  /// This function will return a list of `EquationRowNode` along with a list
  /// of line breaking penalties.
  ///
  /// {@macro flutter_math_fork.widgets.math.tex_break}
  BreakResult<EquationRowNode> texBreak({
    int relPenalty = 500,
    int binOpPenalty = 700,
    bool enforceNoBreak = true,
  }) {
    final breakIndices = <int>[];
    final penalties = <int>[];
    for (var i = 0; i < flattenedChildList.length; i++) {
      final child = flattenedChildList[i];

      // Peek ahead to see if the next child is a no-break
      if (i < flattenedChildList.length - 1) {
        final nextChild = flattenedChildList[i + 1];
        if (nextChild is SpaceNode &&
            nextChild.breakPenalty != null &&
            nextChild.breakPenalty! >= 10000) {
          if (!enforceNoBreak) {
            // The break point should be moved to the next child, which is a \nobreak.
            continue;
          } else {
            // In enforced mode, we should cancel the break point all together.
            i++;
            continue;
          }
        }
      }

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
    }

    final res = <EquationRowNode>[];
    var pos = 1;
    for (var i = 0; i < breakIndices.length; i++) {
      final breakEnd = caretPositions[breakIndices[i] + 1];
      res.add(this.clipChildrenBetween(pos, breakEnd).wrapWithEquationRow());
      pos = breakEnd;
    }
    if (pos != caretPositions.last) {
      res.add(this
          .clipChildrenBetween(pos, caretPositions.last)
          .wrapWithEquationRow());
      penalties.add(10000);
    }
    return BreakResult<EquationRowNode>(
      parts: res,
      penalties: penalties,
    );
  }
}

class BreakResult<T> {
  final List<T> parts;
  final List<int> penalties;

  const BreakResult({
    required this.parts,
    required this.penalties,
  });
}

/// Result of splitting an [EquationRowNode] at its top-level [CrNode]s.
class NewlineSplitResult {
  /// One [EquationRowNode] per line (without the separating [CrNode]s).
  final List<EquationRowNode> lines;

  /// Extra vertical gap after each line, taken from the separating `\\[size]`.
  ///
  /// `gaps[i]` is the gap between `lines[i]` and `lines[i + 1]`; length is
  /// always exactly `lines.length - 1`.
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
