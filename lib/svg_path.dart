/// An SVG path-data parser that flattens to polylines.
///
/// Pure Dart on purpose. The UI builds a `ui.Path` from the same command
/// list for painting, but everything that has to *reason* about the art —
/// where the trace guide runs, which region a finger landed in — works on
/// the flattened points here, with no device and no engine involved.
///
/// Supports M, L, H, V, C, S, Q, T, Z in both cases. Arcs (A) are not
/// supported: nothing in the asset set needs them, and silently mis-drawing
/// one would be worse than refusing it.
library;

import 'geometry.dart';

/// One drawing command, already in absolute coordinates.
sealed class PathCommand {
  const PathCommand();
}

class MoveTo extends PathCommand {
  const MoveTo(this.to);
  final Vec2 to;
}

class LineTo extends PathCommand {
  const LineTo(this.to);
  final Vec2 to;
}

class CubicTo extends PathCommand {
  const CubicTo(this.c1, this.c2, this.to);
  final Vec2 c1, c2, to;
}

class QuadraticTo extends PathCommand {
  const QuadraticTo(this.c, this.to);
  final Vec2 c, to;
}

class ClosePath extends PathCommand {
  const ClosePath();
}

class SvgPathException implements Exception {
  SvgPathException(this.message);
  final String message;
  @override
  String toString() => 'SvgPathException: $message';
}

/// A parsed path: the commands for painting, and the flattened subpaths
/// for geometry.
class ParsedPath {
  ParsedPath(this.commands, this.subpaths);

  final List<PathCommand> commands;

  /// One polyline per subpath. A closed subpath repeats its first point at
  /// the end, so distance-to-outline covers the closing edge too — without
  /// that, the seam where a shape joins up reads as "not on the line".
  final List<List<Vec2>> subpaths;

  /// Every point of every subpath, in order. The trace guide treats the
  /// whole outline as one thing to be near.
  List<Vec2> get allPoints => [for (final s in subpaths) ...s];

  Bounds get bounds => Bounds.around(allPoints);
}

/// Parses SVG path data, flattening curves into [segmentsPerCurve] line
/// segments each.
///
/// Fixed subdivision rather than adaptive: asset curves are authored at a
/// known 1024-unit scale, 16 segments is visually exact there, and a fixed
/// count keeps the flattening deterministic — which is what lets the tests
/// assert on point counts at all.
ParsedPath parseSvgPath(String d, {int segmentsPerCurve = 16}) {
  final tokens = _tokenise(d);
  final commands = <PathCommand>[];
  final subpaths = <List<Vec2>>[];

  List<Vec2>? current;
  var cursor = const Vec2(0, 0);
  var subpathStart = const Vec2(0, 0);
  // Reflection anchor for the smooth variants (S, T). Null when the
  // previous command was not a curve of the matching kind, in which case
  // SVG says the control point coincides with the cursor.
  Vec2? lastCubicControl;
  Vec2? lastQuadControl;

  void begin(Vec2 p) {
    current = [p];
    subpaths.add(current!);
  }

  void extend(Vec2 p) {
    current ??= (() {
      begin(cursor);
      return current!;
    })();
    current!.add(p);
  }

  var i = 0;
  String? op;

  double number() {
    if (i >= tokens.length) {
      throw SvgPathException('ran out of numbers after "$op"');
    }
    final t = tokens[i++];
    final v = double.tryParse(t);
    if (v == null) throw SvgPathException('expected a number, got "$t"');
    return v;
  }

  while (i < tokens.length) {
    final token = tokens[i];
    if (double.tryParse(token) == null) {
      op = token;
      i++;
    } else if (op == null) {
      throw SvgPathException('path data starts with a number, not a command');
    } else if (op == 'M') {
      // A repeated coordinate pair after M means an implicit L, per spec.
      op = 'L';
    } else if (op == 'm') {
      op = 'l';
    }

    final relative = op == op.toLowerCase();
    final base = relative ? cursor : const Vec2(0, 0);

    switch (op.toUpperCase()) {
      case 'M':
        final p = Vec2(number(), number()) + base;
        commands.add(MoveTo(p));
        cursor = p;
        subpathStart = p;
        begin(p);
        lastCubicControl = null;
        lastQuadControl = null;
      case 'L':
        final p = Vec2(number(), number()) + base;
        commands.add(LineTo(p));
        extend(p);
        cursor = p;
        lastCubicControl = null;
        lastQuadControl = null;
      case 'H':
        final x = number() + (relative ? cursor.x : 0);
        final p = Vec2(x, cursor.y);
        commands.add(LineTo(p));
        extend(p);
        cursor = p;
        lastCubicControl = null;
        lastQuadControl = null;
      case 'V':
        final y = number() + (relative ? cursor.y : 0);
        final p = Vec2(cursor.x, y);
        commands.add(LineTo(p));
        extend(p);
        cursor = p;
        lastCubicControl = null;
        lastQuadControl = null;
      case 'C':
        final c1 = Vec2(number(), number()) + base;
        final c2 = Vec2(number(), number()) + base;
        final to = Vec2(number(), number()) + base;
        commands.add(CubicTo(c1, c2, to));
        _flattenCubic(cursor, c1, c2, to, segmentsPerCurve, extend);
        cursor = to;
        lastCubicControl = c2;
        lastQuadControl = null;
      case 'S':
        // Smooth cubic: first control is the previous second control
        // mirrored through the cursor.
        final c1 = lastCubicControl == null
            ? cursor
            : cursor * 2 - lastCubicControl;
        final c2 = Vec2(number(), number()) + base;
        final to = Vec2(number(), number()) + base;
        commands.add(CubicTo(c1, c2, to));
        _flattenCubic(cursor, c1, c2, to, segmentsPerCurve, extend);
        cursor = to;
        lastCubicControl = c2;
        lastQuadControl = null;
      case 'Q':
        final c = Vec2(number(), number()) + base;
        final to = Vec2(number(), number()) + base;
        commands.add(QuadraticTo(c, to));
        _flattenQuadratic(cursor, c, to, segmentsPerCurve, extend);
        cursor = to;
        lastQuadControl = c;
        lastCubicControl = null;
      case 'T':
        final c =
            lastQuadControl == null ? cursor : cursor * 2 - lastQuadControl;
        final to = Vec2(number(), number()) + base;
        commands.add(QuadraticTo(c, to));
        _flattenQuadratic(cursor, c, to, segmentsPerCurve, extend);
        cursor = to;
        lastQuadControl = c;
        lastCubicControl = null;
      case 'Z':
        commands.add(const ClosePath());
        // Repeat the start point so the closing edge is a real segment in
        // the polyline, not an implied one the geometry can't see.
        if (current != null && current!.isNotEmpty) extend(subpathStart);
        cursor = subpathStart;
        current = null;
        lastCubicControl = null;
        lastQuadControl = null;
      default:
        throw SvgPathException('unsupported command "$op"');
    }
  }

  // A subpath of one point draws nothing and would give the geometry a
  // degenerate polyline to divide by.
  subpaths.removeWhere((s) => s.length < 2);
  return ParsedPath(commands, subpaths);
}

void _flattenCubic(
  Vec2 from,
  Vec2 c1,
  Vec2 c2,
  Vec2 to,
  int segments,
  void Function(Vec2) emit,
) {
  for (var i = 1; i <= segments; i++) {
    final t = i / segments;
    final u = 1 - t;
    final p = from * (u * u * u) +
        c1 * (3 * u * u * t) +
        c2 * (3 * u * t * t) +
        to * (t * t * t);
    emit(p);
  }
}

void _flattenQuadratic(
  Vec2 from,
  Vec2 c,
  Vec2 to,
  int segments,
  void Function(Vec2) emit,
) {
  for (var i = 1; i <= segments; i++) {
    final t = i / segments;
    final u = 1 - t;
    final p = from * (u * u) + c * (2 * u * t) + to * (t * t);
    emit(p);
  }
}

/// Splits path data into command letters and numbers.
///
/// Hand-rolled rather than a regex because SVG number syntax has two traps
/// a naive split on whitespace/commas misses: a minus sign starts a new
/// number without a separator ("10-5" is two numbers), and so does a second
/// decimal point (".5.5" is two). Both appear in real exporter output.
List<String> _tokenise(String d) {
  final out = <String>[];
  final buf = StringBuffer();

  void flush() {
    if (buf.isNotEmpty) {
      out.add(buf.toString());
      buf.clear();
    }
  }

  var seenDot = false;
  var seenDigit = false;
  for (var i = 0; i < d.length; i++) {
    final ch = d[i];
    final code = ch.codeUnitAt(0);
    final isDigit = code >= 0x30 && code <= 0x39;

    if (isDigit) {
      buf.write(ch);
      seenDigit = true;
    } else if (ch == '.') {
      if (seenDot) {
        flush();
        seenDigit = false;
      }
      buf.write(ch);
      seenDot = true;
    } else if (ch == '-' || ch == '+') {
      // An exponent's sign belongs to the number in progress; any other
      // sign begins a new one.
      final prev = buf.isEmpty ? '' : buf.toString()[buf.length - 1];
      if (prev == 'e' || prev == 'E') {
        buf.write(ch);
      } else {
        flush();
        seenDot = false;
        seenDigit = false;
        buf.write(ch);
      }
    } else if ((ch == 'e' || ch == 'E') && seenDigit) {
      buf.write(ch);
    } else if (ch == ',' || ch == ' ' || ch == '\n' || ch == '\t' ||
        ch == '\r') {
      flush();
      seenDot = false;
      seenDigit = false;
    } else {
      // A command letter.
      flush();
      seenDot = false;
      seenDigit = false;
      out.add(ch);
    }
  }
  flush();
  return out;
}
