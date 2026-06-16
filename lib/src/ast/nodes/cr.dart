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
