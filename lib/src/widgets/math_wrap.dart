import 'package:flutter/widgets.dart';

import '../ast/style.dart';
import '../parser/tex/settings.dart';
import 'math.dart';

/// Renders a TeX equation that wraps across multiple lines.
///
/// Combines soft line breaking ([Math.texBreak], which breaks after `bin`/`rel`
/// atoms when the line runs out of width) with hard breaks from `\\`, `\cr` and
/// `\newline` (forced break points). The pieces are laid out in a [Wrap], so the
/// equation flows onto as many lines as needed for the available width and always
/// breaks where the author wrote `\\`.
///
/// Must be given a bounded width, like any [Wrap].
class MathWrap extends StatelessWidget {
  /// The underlying equation whose break points drive the layout.
  final Math math;

  /// Cross-axis alignment of the pieces within one line.
  final WrapCrossAlignment crossAxisAlignment;

  const MathWrap({
    Key? key,
    required this.math,
    this.crossAxisAlignment = WrapCrossAlignment.center,
  }) : super(key: key);

  /// Builds a [MathWrap] from a TeX string. Mirrors [Math.tex].
  factory MathWrap.tex(
    String expression, {
    Key? key,
    TextStyle? textStyle,
    MathStyle mathStyle = MathStyle.display,
    OnErrorFallback onErrorFallback = Math.defaultOnErrorFallback,
    TexParserSettings settings = const TexParserSettings(),
    double? textScaleFactor,
    WrapCrossAlignment crossAxisAlignment = WrapCrossAlignment.center,
  }) =>
      MathWrap(
        key: key,
        crossAxisAlignment: crossAxisAlignment,
        math: Math.tex(
          expression,
          textStyle: textStyle,
          mathStyle: mathStyle,
          onErrorFallback: onErrorFallback,
          settings: settings,
          textScaleFactor: textScaleFactor,
        ),
      );

  /// Penalty that [Math.texBreak] assigns to a manual `\\` / `\cr` / `\newline`.
  /// Anything at or below it is a forced (mandatory) break.
  static const int forcedBreakPenalty = -10000;

  @override
  Widget build(BuildContext context) {
    final breakResult = math.texBreak();
    final children = <Widget>[];
    for (var i = 0; i < breakResult.parts.length; i++) {
      children.add(breakResult.parts[i]);
      if (i < breakResult.penalties.length &&
          breakResult.penalties[i] <= forcedBreakPenalty) {
        // A full-width, zero-height spacer fills the rest of the current run,
        // forcing the next piece onto a new line — i.e. a hard `\\` break.
        children.add(const SizedBox(width: double.infinity, height: 0));
      }
    }
    return Wrap(crossAxisAlignment: crossAxisAlignment, children: children);
  }
}
