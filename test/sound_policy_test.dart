import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kidsdreamland/sound_policy.dart';

void main() {
  group('throttling', () {
    test('the first request always plays', () {
      final p = SoundPolicy(random: Random(1));
      expect(p.request(Sfx.tap, 0), isNotNull);
    });

    test('a repeat inside the window is dropped', () {
      final p = SoundPolicy(random: Random(1));
      p.request(Sfx.tap, 0);
      expect(p.request(Sfx.tap, 10), isNull);
      expect(p.request(Sfx.tap, kMinIntervalMs[Sfx.tap]!), isNotNull);
    });

    test('a fast drag over fill regions does not machine-gun', () {
      final p = SoundPolicy(random: Random(1));
      var played = 0;
      // 500ms of drag delivering an event every 4ms.
      for (var t = 0; t < 500; t += 4) {
        if (p.request(Sfx.draw, t) != null) played++;
      }
      // Throttled to the draw interval, not 125 separate sounds.
      expect(played, lessThanOrEqualTo(500 ~/ kMinIntervalMs[Sfx.draw]! + 1));
      expect(played, greaterThan(0));
    });

    test('effects throttle independently of each other', () {
      final p = SoundPolicy(random: Random(1));
      p.request(Sfx.tap, 0);
      // A different effect at the same instant is a different sound and
      // must not be swallowed by the first one's window.
      expect(p.request(Sfx.fill, 0), isNotNull);
    });

    test('the celebration cannot double up on itself', () {
      final p = SoundPolicy(random: Random(1));
      expect(p.request(Sfx.complete, 0), isNotNull);
      expect(p.request(Sfx.complete, 800), isNull);
      expect(p.request(Sfx.complete, 1600), isNotNull);
    });
  });

  group('mute', () {
    test('muted drops everything', () {
      final p = SoundPolicy(random: Random(1), muted: true);
      expect(p.request(Sfx.tap, 0), isNull);
      expect(p.request(Sfx.complete, 0), isNull);
    });

    test('unmuting responds to the very next tap', () {
      final p = SoundPolicy(random: Random(1));
      p.request(Sfx.tap, 0);
      p.muted = true;
      p.muted = false;
      // Without clearing the history, this tap would be eaten by a window
      // that expired silently while muted.
      expect(p.request(Sfx.tap, 1), isNotNull);
    });
  });

  group('pitch', () {
    test('jitter stays inside its declared band', () {
      final p = SoundPolicy(random: Random(7));
      final rates = <double>[];
      for (var t = 0; t < 20000; t += 100) {
        final cue = p.request(Sfx.tap, t);
        if (cue != null) rates.add(cue.rate);
      }
      expect(rates.length, greaterThan(50));
      final band = kPitchJitter[Sfx.tap]!;
      expect(rates.every((r) => r >= 1 - band && r <= 1 + band), isTrue);
      // It must actually vary, or the fiftieth press sounds like the first.
      expect(rates.toSet().length, greaterThan(20));
    });

    test('jitter averages out at the sample pitch rather than drifting', () {
      final p = SoundPolicy(random: Random(3));
      final rates = <double>[];
      for (var t = 0; t < 40000; t += 100) {
        final cue = p.request(Sfx.tap, t);
        if (cue != null) rates.add(cue.rate);
      }
      final mean = rates.reduce((a, b) => a + b) / rates.length;
      expect(mean, closeTo(1.0, 0.01));
    });

    test('the celebration is always the same pitch', () {
      final p = SoundPolicy(random: Random(1));
      for (var t = 0; t < 20000; t += 2000) {
        final cue = p.request(Sfx.complete, t);
        if (cue != null) expect(cue.rate, 1.0);
      }
    });

    test('the palette reads as a rising scale', () {
      final rates = [for (var i = 0; i < 6; i++) SoundPolicy.colorRate(i, 6)];
      expect(rates.first, 1.0);
      expect(rates.last, closeTo(1.5, 1e-9));
      for (var i = 1; i < rates.length; i++) {
        expect(rates[i], greaterThan(rates[i - 1]));
      }
    });

    test('a one-colour palette does not divide by zero', () {
      expect(SoundPolicy.colorRate(0, 1), 1.0);
      expect(SoundPolicy.colorRate(0, 0), 1.0);
    });
  });
}
