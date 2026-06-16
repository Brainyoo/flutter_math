import 'package:flutter_math_fork/src/ast/tex_break.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helper.dart';

void main() {
  group('CrNode renderability', () {
    test('standalone \\\\ builds without crashing', () {
      expect(r'a \\ b', toBuild);
    });

    test('standalone \\cr and \\newline build', () {
      expect(r'a \cr b', toBuild);
      expect(r'a \newline b', toBuild);
    });

    test('\\\\ inside a group builds (baseline path)', () {
      // The CrNode is built inside a Line here, so it must report a baseline.
      expect(r'{a \\ b}', toBuild);
    });

    test('environments with \\\\ still build', () {
      expect(r'\begin{matrix} a & b \\ c & d \end{matrix}', toBuild);
      expect(r'\begin{aligned} a &= b \\ c &= d \end{aligned}', toBuild);
      expect(r'\begin{cases} a & b \\ c & d \end{cases}', toBuild);
    });
  });

  group('texBreak with CrNode', () {
    test('texBreak splits at \\\\', () {
      final result = getParsed(r'a \\ b').texBreak();
      expect(result.parts.length, 2);
      expect(result.penalties.first, -10000); // mandatory break sentinel
    });

    test('texBreak splits at \\cr', () {
      final result = getParsed(r'a \cr b').texBreak();
      expect(result.parts.length, 2);
    });

    test('texBreak does not split plain expression', () {
      final result = getParsed(r'a b').texBreak();
      expect(result.parts.length, 1);
    });
  });
}
