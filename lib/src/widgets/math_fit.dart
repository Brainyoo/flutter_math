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

  /// Vertical gap inserted between stacked lines (both hard `\\` breaks and
  /// soft-wrapped rows).
  final double lineSpacing;

  /// When true, scrollable lines fade out at the edge that has more content,
  /// to signal horizontal scrollability.
  final bool scrollFade;

  const MathFit.tex(
    this.expression, {
    Key? key,
    this.textStyle,
    this.mathStyle = MathStyle.display,
    this.onErrorFallback = Math.defaultOnErrorFallback,
    this.settings = const TexParserSettings(),
    this.textScaleFactor,
    this.crossAxisAlignment = WrapCrossAlignment.center,
    this.lineSpacing = 0.0,
    this.scrollFade = false,
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
        final lineWidgets = <Widget>[
          for (final line in lines)
            if (widget.scrollFade)
              _ScrollFade(
                child: _WrapOrRow(
                  availableWidth: availableWidth,
                  crossAxisAlignment: widget.crossAxisAlignment,
                  runSpacing: widget.lineSpacing,
                  children: line,
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _WrapOrRow(
                  availableWidth: availableWidth,
                  crossAxisAlignment: widget.crossAxisAlignment,
                  runSpacing: widget.lineSpacing,
                  children: line,
                ),
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
      },
    );
  }
}

/// Greedy horizontal wrap that wraps to [availableWidth] (passed explicitly,
/// because inside a horizontal scroll view the incoming constraints are
/// unbounded). A single child wider than [availableWidth] gets its own row that
/// overflows — the enclosing horizontal scroll view then scrolls.
class _WrapOrRow extends MultiChildRenderObjectWidget {
  final double availableWidth;
  final WrapCrossAlignment crossAxisAlignment;
  final double runSpacing;

  const _WrapOrRow({
    required this.availableWidth,
    required this.crossAxisAlignment,
    required List<Widget> children,
    this.runSpacing = 0.0,
  }) : super(children: children);

  @override
  _RenderWrapOrRow createRenderObject(BuildContext context) => _RenderWrapOrRow(
        availableWidth: availableWidth,
        crossAxisAlignment: crossAxisAlignment,
        runSpacing: runSpacing,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderWrapOrRow renderObject) {
    renderObject
      ..availableWidth = availableWidth
      ..crossAxisAlignment = crossAxisAlignment
      ..runSpacing = runSpacing;
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
    double runSpacing = 0.0,
  })  : _availableWidth = availableWidth,
        _crossAxisAlignment = crossAxisAlignment,
        _runSpacing = runSpacing;

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

  double _runSpacing;
  set runSpacing(double value) {
    if (_runSpacing != value) {
      _runSpacing = value;
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

    child = firstChild;
    while (child != null) {
      final s = sizes[child]!;
      if (row.isNotEmpty && rowWidth + s.width > _availableWidth) {
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
    final totalHeight = rowHeights.fold<double>(0.0, (a, b) => a + b) +
        (rows.isEmpty ? 0.0 : _runSpacing * (rows.length - 1));
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
      if (r < rows.length - 1) y += _runSpacing;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// Fades the horizontally-scrollable edges of [child] to signal scrollability:
/// the right edge fades while more content remains, the left edge fades once
/// scrolled. No fade when the content fits.
class _ScrollFade extends StatefulWidget {
  final Widget child;

  const _ScrollFade({required this.child});

  @override
  State<_ScrollFade> createState() => _ScrollFadeState();
}

class _ScrollFadeState extends State<_ScrollFade> {
  static const double _fadeWidth = 24.0;
  static const Color _opaque = Color(0xFFFFFFFF);
  static const Color _clear = Color(0x00000000);

  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
    // After the first layout the scroll metrics exist; recompute so an initial
    // right-edge fade shows when the content overflows.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasClients = _controller.hasClients;
    final fadeLeft = hasClients && _controller.position.extentBefore > 0;
    final fadeRight = hasClients && _controller.position.extentAfter > 0;

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        // Metrics changed (relayout/resize) — recompute after this frame to
        // avoid setState during layout.
        WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
        return false;
      },
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (Rect rect) {
          if (!fadeLeft && !fadeRight) {
            return const LinearGradient(colors: [_opaque, _opaque])
                .createShader(rect);
          }
          final f =
              rect.width <= 0 ? 0.0 : (_fadeWidth / rect.width).clamp(0.0, 0.5);
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              fadeLeft ? _clear : _opaque,
              _opaque,
              _opaque,
              fadeRight ? _clear : _opaque,
            ],
            stops: [0.0, f, 1 - f, 1.0],
          ).createShader(rect);
        },
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: widget.child,
        ),
      ),
    );
  }
}
