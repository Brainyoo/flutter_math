import 'package:flutter/widgets.dart';

import '../ast/style.dart';
import '../parser/tex/settings.dart';
import 'math.dart';
import 'multiline_math.dart';

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
  @Deprecated('Use mathForcedBreakPenalty from multiline_math.dart instead.')
  static const int forcedBreakPenalty = mathForcedBreakPenalty;

  /// Number of times any [MathWrap] recomputed its break result. For tests only.
  @visibleForTesting
  static int debugRecomputeCount = 0;

  @override
  State<MathWrap> createState() => _MathWrapState();
}

class _MathWrapState extends State<MathWrap>
    with MathBreakStateMixin<MathWrap> {
  @override
  MathBreakInputs get breakInputs => MathBreakInputs(
        expression: widget.expression,
        textStyle: widget.textStyle,
        mathStyle: widget.mathStyle,
        onErrorFallback: widget.onErrorFallback,
        settings: widget.settings,
        textScaleFactor: widget.textScaleFactor,
      );

  @override
  void onRecompute() => MathWrap.debugRecomputeCount++;

  @override
  Widget build(BuildContext context) {
    final lineWidgets = <Widget>[
      for (final line in groupBreakResultIntoLines(breakResult))
        if (line.isBlank)
          SizedBox(
            height: resolveBlankLineHeight(
                context, widget.textStyle, widget.textScaleFactor),
          )
        else
          Wrap(
            crossAxisAlignment: widget.crossAxisAlignment,
            runSpacing: widget.lineSpacing,
            children: line.parts,
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
