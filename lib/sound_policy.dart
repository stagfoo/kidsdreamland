/// Deciding *whether* and *how* to play a sound — separately from playing
/// it.
///
/// The interesting rules here are the ones that stop the sonic palette
/// becoming a machine gun, and they are pure functions of a clock and a
/// random source. Both are injected, so the tests drive them exactly rather
/// than sleeping and hoping.
library;

import 'dart:math' as math;

enum Sfx {
  tap,
  colorSelect,
  draw,
  fill,
  complete,
  transition,
  mascot,
}

/// How often each effect may fire, in milliseconds.
///
/// `draw` is the aggressive one: it loops while a finger drags, and a drag
/// delivers events every few milliseconds. `complete` is throttled hard
/// because two celebrations on top of each other sounds like a mistake.
const Map<Sfx, int> kMinIntervalMs = {
  Sfx.tap: 40,
  Sfx.colorSelect: 60,
  Sfx.draw: 90,
  Sfx.fill: 120,
  Sfx.complete: 1500,
  Sfx.transition: 200,
  Sfx.mascot: 400,
};

/// How far the pitch may wander, per effect.
///
/// Repetition is what makes a short sample sound robotic by the fiftieth
/// press, and a few percent of pitch is enough to break it up. The
/// celebration gets none: it should sound the same every time it is
/// earned, because it is the one sound that means something.
const Map<Sfx, double> kPitchJitter = {
  Sfx.tap: 0.08,
  Sfx.colorSelect: 0.0, // pitch is carried by which colour, below
  Sfx.draw: 0.05,
  Sfx.fill: 0.06,
  Sfx.complete: 0.0,
  Sfx.transition: 0.04,
  Sfx.mascot: 0.10,
};

class SoundCue {
  const SoundCue(this.sfx, this.rate, this.volume);

  final Sfx sfx;

  /// Playback rate, which on a short sample is heard as pitch.
  final double rate;

  final double volume;
}

/// Answers "should this sound play right now, and at what pitch".
///
/// Holds no audio and touches no plugin — it is the part of the sound layer
/// worth being sure about, and it runs in a unit test at full speed.
class SoundPolicy {
  SoundPolicy({math.Random? random, bool muted = false})
      : _random = random ?? math.Random(),
        // Named `muted` rather than taking `this._muted`, so callers are
        // not asked to know about a private field.
        // ignore: prefer_initializing_formals
        _muted = muted;

  final math.Random _random;
  final Map<Sfx, int> _lastPlayedMs = {};

  bool _muted;
  bool get muted => _muted;
  set muted(bool value) {
    _muted = value;
    // Clearing the history means unmuting is instantly responsive rather
    // than swallowing the first tap because of a throttle that expired
    // silently while muted.
    if (!value) _lastPlayedMs.clear();
  }

  /// Returns the cue to play, or null if this one should be dropped.
  ///
  /// [nowMs] is passed in rather than read from a clock so the throttling
  /// is deterministic under test.
  SoundCue? request(Sfx sfx, int nowMs, {double volume = 1.0}) {
    if (_muted) return null;

    final last = _lastPlayedMs[sfx];
    final minGap = kMinIntervalMs[sfx] ?? 0;
    if (last != null && nowMs - last < minGap) return null;
    _lastPlayedMs[sfx] = nowMs;

    final jitter = kPitchJitter[sfx] ?? 0;
    // Symmetric around 1.0, so a long run of sounds averages out at the
    // sample's own pitch instead of drifting sharp or flat.
    final rate = jitter == 0
        ? 1.0
        : 1.0 + (_random.nextDouble() * 2 - 1) * jitter;
    return SoundCue(sfx, rate, volume);
  }

  /// The pitch for picking the [index]-th colour of [count].
  ///
  /// A rising scale across the palette, so the colours have an order you
  /// can hear — the reason the palette strip is worth touching for its own
  /// sake at this age. Spread over a fifth (1.0 to 1.5); a full octave
  /// makes the last colour shrill on a tablet speaker.
  static double colorRate(int index, int count) {
    if (count <= 1) return 1.0;
    return 1.0 + (index / (count - 1)) * 0.5;
  }

  void reset() => _lastPlayedMs.clear();
}
