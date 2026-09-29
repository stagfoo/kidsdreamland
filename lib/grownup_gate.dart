/// The door between the child's app and the adult's tool.
///
/// Everything past this point breaks the app's own rules — it has words
/// in it, it has fields to type in, it can delete things. That is fine,
/// because it is not for the audience. What matters is that the audience
/// cannot arrive here by poking, and cannot arrive here by accident while
/// showing a grandparent the dinosaur.
///
/// The gate is a hold, not a password. A password is a thing to lose; a
/// four-second deliberate press is something a five-year-old does not do,
/// does not discover, and would let go of long before it opened. And it
/// needs no reading: the ring fills while you hold, which is the whole
/// instruction.
library;

import 'package:flutter/material.dart';

import 'theme.dart';

/// How long the second, confirming hold lasts. Long enough to be a
/// decision, short enough that an adult does not think it is broken.
const Duration kGateHold = Duration(milliseconds: 2200);

/// The first hold, on the mascot. Shorter, because on its own it opens
/// nothing — it only offers the gate.
const Duration kGateSummon = Duration(milliseconds: 1500);

/// A full-screen hold-to-continue. Pops with `true` once held.
class GrownupGate extends StatefulWidget {
  const GrownupGate({super.key});

  @override
  State<GrownupGate> createState() => _GrownupGateState();
}

class _GrownupGateState extends State<GrownupGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: kGateHold,
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        Navigator.of(context).pop(true);
      }
    });

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Sky.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Listener(
              onPointerDown: (_) => _hold.forward(),
              // Releasing rewinds rather than pausing: a hold interrupted
              // half way and picked up again is a different decision, and
              // resuming from 90% would make the gate far easier to trip
              // by accident than it looks.
              onPointerUp: (_) => _hold.reverse(),
              onPointerCancel: (_) => _hold.reverse(),
              child: AnimatedBuilder(
                animation: _hold,
                builder: (context, child) => SizedBox(
                  width: 160,
                  height: 160,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 160,
                        height: 160,
                        child: CircularProgressIndicator(
                          value: _hold.value,
                          strokeWidth: 10,
                          backgroundColor: Sky.accentSoft,
                          valueColor: const AlwaysStoppedAnimation(
                            Sky.accent,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.edit_rounded,
                        size: 56,
                        color: Sky.accent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Hold to open the art tool',
              style: TextStyle(
                fontSize: 18,
                color: Sky.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 40),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
