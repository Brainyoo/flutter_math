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
    // Group the pieces into lines, splitting at forced (`\\`) breaks. Each line
    // is its own [Wrap], so it soft-wraps to the available width; the lines are
    // stacked in a [Column]. Unlike a single [Wrap] with a full-width spacer,
    // this sizes to the widest line (shrink-wraps) instead of always filling the
    // available width — so the block can be centred or laid out freely.
    final lines = <List<Widget>>[<Widget>[]];
    for (var i = 0; i < breakResult.parts.length; i++) {
      lines.last.add(breakResult.parts[i]);
      final isForcedBreak = i < breakResult.penalties.length &&
          breakResult.penalties[i] <= forcedBreakPenalty;
      if (isForcedBreak && i < breakResult.parts.length - 1) {
        lines.add(<Widget>[]);
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Wrap(crossAxisAlignment: crossAxisAlignment, children: line),
      ],
    );
  }
}
