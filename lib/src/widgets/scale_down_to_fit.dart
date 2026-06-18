import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Scales [child] down so it fits the available width, but never below
/// [minScale]. If the child would still overflow at [minScale], it stays at
/// [minScale] and becomes horizontally scrollable instead of being clipped or
/// shrunk into illegibility.
///
/// Intended to wrap a single-line equation (e.g. `Math.tex(...)`) so a wide
/// formula gently fits a small screen. For multi-line wrapping use `MathWrap`
/// instead — the two are alternative strategies, not nested (nesting a
/// `MathWrap` here would defeat its wrapping and overflow on the `\\` spacer).
///
/// Needs a bounded width to measure against.
///
/// Does not support intrinsic sizing: it lays out via a [LayoutBuilder], which
/// cannot answer intrinsic-dimension queries. Placing it under a parent that
/// probes intrinsics ([IntrinsicWidth], [IntrinsicHeight], a baseline-aligned
/// [Row], or some [Table] configurations) throws at layout time. Give it
/// bounded constraints directly instead.
class ScaleDownToFit extends StatelessWidget {
  /// Lower bound on the scale factor. Below this the child scrolls instead of
  /// shrinking further. Must be in (0, 1].
  final double minScale;

  final Widget child;

  const ScaleDownToFit({
    Key? key,
    this.minScale = 0.6,
    required this.child,
  })  : assert(minScale > 0 && minScale <= 1),
        super(key: key);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _ScaleToFit(
            availableWidth: constraints.maxWidth,
            minScale: minScale,
            child: child,
          ),
        ),
      );
}

class _ScaleToFit extends SingleChildRenderObjectWidget {
  final double availableWidth;
  final double minScale;

  const _ScaleToFit({
    required this.availableWidth,
    required this.minScale,
    required Widget child,
  }) : super(child: child);

  @override
  _RenderScaleToFit createRenderObject(BuildContext context) =>
      _RenderScaleToFit(availableWidth: availableWidth, minScale: minScale);

  @override
  void updateRenderObject(
      BuildContext context, _RenderScaleToFit renderObject) {
    renderObject
      ..availableWidth = availableWidth
      ..minScale = minScale;
  }
}

class _RenderScaleToFit extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  _RenderScaleToFit({
    required double availableWidth,
    required double minScale,
  })  : _availableWidth = availableWidth,
        _minScale = minScale;

  double _availableWidth;
  double get availableWidth => _availableWidth;
  set availableWidth(double value) {
    if (_availableWidth != value) {
      _availableWidth = value;
      markNeedsLayout();
    }
  }

  double _minScale;
  double get minScale => _minScale;
  set minScale(double value) {
    if (_minScale != value) {
      _minScale = value;
      markNeedsLayout();
    }
  }

  double _scale = 1.0;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    // Natural (unconstrained) size, then scale to fit the available width.
    child.layout(const BoxConstraints(), parentUsesSize: true);
    final w = child.size.width;
    _scale = (w <= _availableWidth || w == 0)
        ? 1.0
        : math.max(_minScale, _availableWidth / w);
    size = constraints
        .constrain(Size(w * _scale, child.size.height * _scale));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (_scale == 1.0) {
      context.paintChild(child, offset);
      return;
    }
    context.pushTransform(
      needsCompositing,
      offset,
      Matrix4.diagonal3Values(_scale, _scale, 1.0),
      (context, offset) => context.paintChild(child, offset),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintTransform(
      transform: Matrix4.diagonal3Values(_scale, _scale, 1.0),
      position: position,
      hitTest: (result, position) =>
          child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.scaleByDouble(_scale, _scale, 1.0, 1.0);
  }
}
