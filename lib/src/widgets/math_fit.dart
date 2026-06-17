import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../ast/style.dart';
import '../ast/tex_break.dart';
import '../parser/tex/settings.dart';
import 'math.dart';
import 'math_wrap.dart';

/// Renders a TeX equation that fits the available width as gracefully as
/// possible:
///  * hard breaks at `\\`, `\cr`, `\newline`;
///  * soft-wraps each line (after `bin`/`rel` atoms) when it is too wide;
///  * and, for a line containing a single element too wide to break (a big
///    fraction, matrix, …), that line scrolls horizontally instead of
///    overflowing.
///
/// Takes the full available width (each line sits in a horizontal scroll
/// viewport, which needs a defined width). This is the sibling of [MathWrap],
/// which shrink-wraps to its content but cannot scroll. Use [MathWrap] when you
/// want a content-sized, centreable block and there are no unbreakable wide
/// elements; use [MathFit] when a line might be too wide to break. Needs a
/// bounded width.
class MathFit extends StatefulWidget {
  final String expression;
  final TextStyle? textStyle;
  final MathStyle mathStyle;
  final OnErrorFallback onErrorFallback;
  final TexParserSettings settings;
  final double? textScaleFactor;

  /// Vertical alignment of the pieces within one (soft-wrapped) run.
  final WrapCrossAlignment crossAxisAlignment;

  const MathFit.tex(
    this.expression, {
    Key? key,
    this.textStyle,
    this.mathStyle = MathStyle.display,
    this.onErrorFallback = Math.defaultOnErrorFallback,
    this.settings = const TexParserSettings(),
    this.textScaleFactor,
    this.crossAxisAlignment = WrapCrossAlignment.center,
  }) : super(key: key);

  /// Number of times any [MathFit] recomputed its break result. For tests only.
  @visibleForTesting
  static int debugRecomputeCount = 0;

  @override
  State<MathFit> createState() => _MathFitState();
}

class _MathFitState extends State<MathFit> {
  late BreakResult<Math> _breakResult;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void didUpdateWidget(covariant MathFit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_inputsChanged(oldWidget)) {
      _recompute();
    }
  }

  bool _inputsChanged(MathFit oldWidget) =>
      widget.expression != oldWidget.expression ||
      widget.textStyle != oldWidget.textStyle ||
      widget.mathStyle != oldWidget.mathStyle ||
      widget.settings != oldWidget.settings ||
      widget.textScaleFactor != oldWidget.textScaleFactor;

  void _recompute() {
    MathFit.debugRecomputeCount++;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _WrapOrRow(
                  availableWidth: availableWidth,
                  crossAxisAlignment: widget.crossAxisAlignment,
                  children: line,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Greedy horizontal wrap that wraps to [availableWidth] (passed explicitly,
/// because inside a horizontal scroll view the incoming constraints are
/// unbounded).
///
/// Normally children are greedy-filled into rows up to [availableWidth]. When
/// ANY child is wider than [availableWidth] (an unbreakable element such as a
/// large fraction or matrix), ALL children are placed on a SINGLE row instead.
/// That row overflows and the enclosing horizontal scroll view scrolls as a
/// unit. This prevents fitting soft-wrapped rows from sharing the scroll offset
/// of the over-wide row and being dragged off-screen.
class _WrapOrRow extends MultiChildRenderObjectWidget {
  final double availableWidth;
  final WrapCrossAlignment crossAxisAlignment;

  const _WrapOrRow({
    required this.availableWidth,
    required this.crossAxisAlignment,
    required List<Widget> children,
  }) : super(children: children);

  @override
  _RenderWrapOrRow createRenderObject(BuildContext context) => _RenderWrapOrRow(
        availableWidth: availableWidth,
        crossAxisAlignment: crossAxisAlignment,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderWrapOrRow renderObject) {
    renderObject
      ..availableWidth = availableWidth
      ..crossAxisAlignment = crossAxisAlignment;
  }
}

class _WrapOrRowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderWrapOrRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _WrapOrRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _WrapOrRowParentData> {
  _RenderWrapOrRow({
    required double availableWidth,
    required WrapCrossAlignment crossAxisAlignment,
  })  : _availableWidth = availableWidth,
        _crossAxisAlignment = crossAxisAlignment;

  double _availableWidth;
  set availableWidth(double value) {
    if (_availableWidth != value) {
      _availableWidth = value;
      markNeedsLayout();
    }
  }

  WrapCrossAlignment _crossAxisAlignment;
  set crossAxisAlignment(WrapCrossAlignment value) {
    if (_crossAxisAlignment != value) {
      _crossAxisAlignment = value;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _WrapOrRowParentData) {
      child.parentData = _WrapOrRowParentData();
    }
  }

  @override
  void performLayout() {
    // Lay every child out at its natural size.
    final sizes = <RenderBox, Size>{};
    var child = firstChild;
    while (child != null) {
      child.layout(const BoxConstraints(), parentUsesSize: true);
      sizes[child] = child.size;
      child = childAfter(child);
    }

    // Greedy-fill rows up to availableWidth. A single child wider than
    // availableWidth ends up alone on an over-wide row.
    final rows = <List<RenderBox>>[];
    final rowWidths = <double>[];
    final rowHeights = <double>[];
    var row = <RenderBox>[];
    var rowWidth = 0.0;
    var rowHeight = 0.0;
    void closeRow() {
      rows.add(row);
      rowWidths.add(rowWidth);
      rowHeights.add(rowHeight);
      row = <RenderBox>[];
      rowWidth = 0.0;
      rowHeight = 0.0;
    }

    // If a single child is wider than the available width, the line can't wrap
    // sensibly: lay it all on one row so it scrolls as a unit (otherwise the
    // fitting rows would share the scroll offset of the over-wide row).
    final hasUnbreakableOverflow =
        sizes.values.any((s) => s.width > _availableWidth);

    child = firstChild;
    while (child != null) {
      final s = sizes[child]!;
      if (!hasUnbreakableOverflow &&
          row.isNotEmpty &&
          rowWidth + s.width > _availableWidth) {
        closeRow();
      }
      row.add(child);
      rowWidth += s.width;
      rowHeight = math.max(rowHeight, s.height);
      child = childAfter(child);
    }
    if (row.isNotEmpty) closeRow();

    final totalWidth =
        rowWidths.isEmpty ? 0.0 : rowWidths.reduce(math.max);
    final totalHeight = rowHeights.fold<double>(0.0, (a, b) => a + b);
    size = constraints.constrain(Size(totalWidth, totalHeight));

    // Position children row by row.
    var y = 0.0;
    for (var r = 0; r < rows.length; r++) {
      var x = 0.0;
      final h = rowHeights[r];
      for (final c in rows[r]) {
        final cs = sizes[c]!;
        final double dy;
        switch (_crossAxisAlignment) {
          case WrapCrossAlignment.start:
            dy = 0.0;
          case WrapCrossAlignment.end:
            dy = h - cs.height;
          case WrapCrossAlignment.center:
            dy = (h - cs.height) / 2;
        }
        (c.parentData as _WrapOrRowParentData).offset = Offset(x, y + dy);
        x += cs.width;
      }
      y += h;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
