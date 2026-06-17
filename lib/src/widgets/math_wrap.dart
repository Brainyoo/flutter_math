import 'package:flutter/widgets.dart';

import '../ast/style.dart';
import '../ast/tex_break.dart';
import '../parser/tex/settings.dart';
import 'math.dart';

/// Renders a TeX equation that wraps across multiple lines, sizing to its
/// content (shrink-wraps) under loose width constraints.
///
/// Combines soft line breaking ([Math.texBreak], after `bin`/`rel` atoms when a
/// line runs out of width) with hard breaks from `\\`, `\cr` and `\newline`.
/// Each hard-break line is its own [Wrap], stacked in a [Column], so the block
/// sizes to the widest line (it can be centred). A single element too wide to
/// break will overflow — use [MathFit] if a line might be unbreakably wide.
///
/// The parse + break work is memoized: rebuilds with the same expression/style
/// reuse the cached result. Needs a bounded width to wrap against.
class MathWrap extends StatefulWidget {
  final String expression;
  final TextStyle? textStyle;
  final MathStyle mathStyle;
  final OnErrorFallback onErrorFallback;
  final TexParserSettings settings;
  final double? textScaleFactor;

  /// Vertical alignment of the pieces within one line.
  final WrapCrossAlignment crossAxisAlignment;

  /// Vertical gap inserted between stacked lines (both hard `\\` breaks and
  /// soft-wrapped rows).
  final double lineSpacing;

  const MathWrap.tex(
    this.expression, {
    Key? key,
    this.textStyle,
    this.mathStyle = MathStyle.display,
    this.onErrorFallback = Math.defaultOnErrorFallback,
    this.settings = const TexParserSettings(),
    this.textScaleFactor,
    this.crossAxisAlignment = WrapCrossAlignment.center,
    this.lineSpacing = 0.0,
  }) : super(key: key);

  /// Penalty that [Math.texBreak] assigns to a manual `\\` / `\cr` / `\newline`.
  /// Anything at or below it is a forced (mandatory) break.
  static const int forcedBreakPenalty = -10000;

  /// Number of times any [MathWrap] recomputed its break result. For tests only.
  @visibleForTesting
  static int debugRecomputeCount = 0;

  @override
  State<MathWrap> createState() => _MathWrapState();
}

class _MathWrapState extends State<MathWrap> {
  late BreakResult<Math> _breakResult;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void didUpdateWidget(covariant MathWrap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_inputsChanged(oldWidget)) {
      _recompute();
    }
  }

  bool _inputsChanged(MathWrap oldWidget) =>
      widget.expression != oldWidget.expression ||
      widget.textStyle != oldWidget.textStyle ||
      widget.mathStyle != oldWidget.mathStyle ||
      widget.settings != oldWidget.settings ||
      widget.textScaleFactor != oldWidget.textScaleFactor;

  void _recompute() {
    MathWrap.debugRecomputeCount++;
    _breakResult = Math
        .tex(
          widget.expression,
          textStyle: widget.textStyle,
          mathStyle: widget.mathStyle,
          onErrorFallback: widget.onErrorFallback,
          settings: widget.settings,
          textScaleFactor: widget.textScaleFactor,
        )
        .texBreak();
  }

  @override
  Widget build(BuildContext context) {
    // Group the cached pieces into lines, splitting at forced (`\\`) breaks.
    final lines = <List<Widget>>[<Widget>[]];
    for (var i = 0; i < _breakResult.parts.length; i++) {
      lines.last.add(_breakResult.parts[i]);
      final forced = i < _breakResult.penalties.length &&
          _breakResult.penalties[i] <= MathWrap.forcedBreakPenalty;
      if (forced && i < _breakResult.parts.length - 1) {
        lines.add(<Widget>[]);
      }
    }
    final lineWidgets = <Widget>[
      for (final line in lines)
        Wrap(
          crossAxisAlignment: widget.crossAxisAlignment,
          runSpacing: widget.lineSpacing,
          children: line,
        ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lineWidgets.length; i++) ...[
          if (i > 0) SizedBox(height: widget.lineSpacing),
          lineWidgets[i],
        ],
      ],
    );
  }
}
