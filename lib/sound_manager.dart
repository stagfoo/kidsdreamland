import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'sound_policy.dart';

/// Plays the sonic palette.
///
/// Every decision about *whether* to play lives in [SoundPolicy], which is
/// pure and tested. This part only owns the players and the plugin, and is
/// deliberately thin — it is the bit that cannot be tested without a
/// device, so there is as little of it as possible.
class SoundManager {
  SoundManager._();

  static final SoundManager instance = SoundManager._();

  static const Map<Sfx, String> _files = {
    Sfx.tap: 'sounds/tap.wav',
    Sfx.colorSelect: 'sounds/color.wav',
    Sfx.draw: 'sounds/draw.wav',
    Sfx.fill: 'sounds/fill.wav',
    Sfx.complete: 'sounds/complete.wav',
    Sfx.transition: 'sounds/transition.wav',
    Sfx.mascot: 'sounds/mascot.wav',
  };

  final SoundPolicy _policy = SoundPolicy();
  final Stopwatch _clock = Stopwatch()..start();

  /// A small pool of players, used round-robin.
  ///
  /// One player per effect would cut a sound off when it retriggers, and
  /// one player overall would cut *every* sound off — a fill landing on
  /// top of a draw scratch is normal, not an error. Six is enough for any
  /// real overlap at the throttle rates in [kMinIntervalMs].
  static const int _poolSize = 6;
  final List<AudioPlayer> _pool = [];
  int _next = 0;
  bool _ready = false;

  bool get muted => _policy.muted;

  /// Notifies the mute button without dragging a state-management package
  /// in for one boolean.
  final ValueNotifier<bool> mutedNotifier = ValueNotifier(false);

  Future<void> init() async {
    if (_ready) return;
    try {
      for (var i = 0; i < _poolSize; i++) {
        final p = AudioPlayer();
        // These are fire-and-forget effects; the low-latency mode skips
        // the machinery for media playback (notifications, focus changes)
        // that a sound effect does not want.
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setReleaseMode(ReleaseMode.stop);
        _pool.add(p);
      }
      _ready = true;
    } catch (e) {
      // A device with no working audio route must not take the drawing
      // app down with it. Silence is a survivable outcome here; a crash
      // on the way into the first screen is not.
      debugPrint('SoundManager: audio unavailable, continuing muted ($e)');
      _ready = false;
    }
  }

  void setMuted(bool value) {
    _policy.muted = value;
    mutedNotifier.value = value;
    if (value) {
      for (final p in _pool) {
        p.stop();
      }
    }
  }

  void toggleMute() => setMuted(!muted);

  /// Plays [sfx] if the policy allows it. [rate] overrides the policy's own
  /// pitch, which is how the palette plays a rising scale.
  void play(Sfx sfx, {double? rate, double volume = 1.0}) {
    final cue = _policy.request(sfx, _clock.elapsedMilliseconds,
        volume: volume);
    if (cue == null || !_ready) return;

    final player = _pool[_next];
    _next = (_next + 1) % _poolSize;
    final file = _files[sfx];
    if (file == null) return;

    // Deliberately not awaited: a sound must never delay the frame that
    // drew the thing it belongs to. Failures are swallowed for the same
    // reason silence beats a crash above.
    () async {
      try {
        await player.stop();
        await player.setPlaybackRate(rate ?? cue.rate);
        await player.setVolume(cue.volume);
        await player.play(AssetSource(file));
      } catch (_) {}
    }();
  }

  /// The pitch for the [index]-th colour of [count].
  double colorRate(int index, int count) =>
      SoundPolicy.colorRate(index, count);

  Future<void> dispose() async {
    for (final p in _pool) {
      await p.dispose();
    }
    _pool.clear();
    _ready = false;
  }
}
