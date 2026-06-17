import 'package:flutter/widgets.dart';

import '../ast/nodes/cr.dart';
import '../ast/style.dart';
import '../ast/tex_break.dart';
import '../parser/tex/settings.dart';
import 'math.dart';

/// Penalty that [Math.texBreak] assigns to a manual `\\` / `\cr` / `\newline`.
/// Anything at or below it is a forced (mandatory) break.
const int mathForcedBreakPenalty = -10000;

/// The break inputs that determine the cached [BreakResult]. Two widgets with
/// equal [MathBreakInputs] reuse the same parse + break result.
///
/// `onErrorFallback` is part of the cache key because parse failures render
/// through the fallback widget.
class MathBreakInputs {
  final String expression;
  final TextStyle? textStyle;
  final MathStyle mathStyle;
  final OnErrorFallback onErrorFallback;
  final TexParserSettings settings;
  final double? textScaleFactor;

  const MathBreakInputs({
    required this.expression,
    required this.textStyle,
    required this.mathStyle,
    required this.onErrorFallback,
    required this.settings,
    required this.textScaleFactor,
  });

  /// Whether [other] would produce the same break result (so the cache can be
  /// reused). The single place that decides which inputs trigger a recompute.
  bool sameBreakInputs(MathBreakInputs other) =>
      expression == other.expression &&
      textStyle == other.textStyle &&
      mathStyle == other.mathStyle &&
      settings == other.settings &&
      onErrorFallback == other.onErrorFallback &&
      textScaleFactor == other.textScaleFactor;
}

/// One stacked line produced by grouping a [BreakResult] at forced breaks.
class MathBreakLine {
  /// The (soft-breakable) pieces that make up this line.
  final List<Math> parts;

  /// True when the line carries no visible content — it consists solely of
  /// break markers (a blank line from `\\\\`). Such a line must still reserve
  /// one line's height instead of collapsing to zero.
  final bool isBlank;

  const MathBreakLine({required this.parts, required this.isBlank});
}

/// Splits a [BreakResult] into stacked lines at forced (`\\`) breaks.
///
/// Soft-break pieces accumulate within the current line; a forced break starts
/// a new line. A trailing forced break does not add an empty line.
List<MathBreakLine> groupBreakResultIntoLines(BreakResult<Math> breakResult) {
  final lines = <List<Math>>[<Math>[]];
  for (var i = 0; i < breakResult.parts.length; i++) {
    lines.last.add(breakResult.parts[i]);
    final forced = i < breakResult.penalties.length &&
        breakResult.penalties[i] <= mathForcedBreakPenalty;
    if (forced && i < breakResult.parts.length - 1) {
      lines.add(<Math>[]);
    }
  }
  return [
    for (final parts in lines)
      // An empty `parts` list only happens for an empty expression; that is not
      // a blank line, it renders as nothing (matching Math.tex('')).
      MathBreakLine(
          parts: parts, isBlank: parts.isNotEmpty && parts.every(_isBlankPart)),
  ];
}

/// A part is blank when its only content is break markers — e.g. the lone
/// [CrNode] part produced for the empty middle line of `a \\\\ b`.
bool _isBlankPart(Math part) {
  final ast = part.ast;
  if (ast == null) return false;
  return ast.greenRoot.flattenedChildList.every((node) => node is CrNode);
}

/// Resolves a blank line's height (logical pixels) the same way [Math] derives
/// `options.fontSize`, so a blank line matches the height of a content line.
double resolveBlankLineHeight(
  BuildContext context,
  TextStyle? textStyle,
  double? textScaleFactor,
) {
  var effective = textStyle;
  if (effective == null || effective.inherit) {
    effective = DefaultTextStyle.of(context).style.merge(textStyle);
  }
  // ignore: deprecated_member_use
  final scale = textScaleFactor ?? MediaQuery.textScaleFactorOf(context);
  return (effective.fontSize ?? 16.0) * scale;
}

/// Memoizes the parse + break work for [MathWrap]/[MathFit]: the result is
/// recomputed only when an input that affects breaking changes.
///
/// The host [State] supplies its widget's [breakInputs] and a [onRecompute]
/// hook (so each widget can bump its own `debugRecomputeCount`).
mixin MathBreakStateMixin<T extends StatefulWidget> on State<T> {
  /// The current widget's break inputs (forward from `widget`).
  MathBreakInputs get breakInputs;

  /// Called once per (re)computation; lets the host bump its recompute counter.
  void onRecompute();

  /// The cached parse + break result.
  late BreakResult<Math> breakResult;

  MathBreakInputs? _cachedInputs;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    final inputs = breakInputs;
    if (_cachedInputs == null || !inputs.sameBreakInputs(_cachedInputs!)) {
      _recompute();
    }
  }

  void _recompute() {
    onRecompute();
    final inputs = breakInputs;
    _cachedInputs = inputs;
    breakResult = Math.tex(
      inputs.expression,
      textStyle: inputs.textStyle,
      mathStyle: inputs.mathStyle,
      onErrorFallback: inputs.onErrorFallback,
      settings: inputs.settings,
      textScaleFactor: inputs.textScaleFactor,
    ).texBreak();
  }
}
