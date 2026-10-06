# King Kids Dream Land — feature PRD

**Status:** draft for review. Nothing here is built yet unless it says so.
**Date:** 2026-10-06
**Against:** v1.0.4
**Target:** [Bimi Boo Drawing](https://bimiboo.net/apps/drawing/) and
[Drawing Pages for Kids](https://bimiboo.net/apps/drawing-pages-for-kids/)

This is a menu, not a plan of record. Strike out what you do not want, reorder
what you do, and answer the open questions at the bottom.

---

## 1. The target, concretely

The Bimi Boo marketing pages are vague; the store listings are not. What those
apps actually ship:

> "Watch your child's completed coloring pages come to life in a short cartoon
> right within the app."

> "Various creative modes include guided outline coloring, freeform sketching,
> kaleidoscopic mirror effects, neon-glitter magic and more."

Plus: colour-by-number and a pixel-art mode added in recent updates; patterns
and templates of stars, rainbows and glitter; 170+ pages across animals,
dinosaurs, cars and dolls; ad-free, offline, ages 2–6; subscription with ~20
free pages.

**The shape of it is six modes over one library of pictures, and a cartoon as
the payoff.** That is the thing to aim at.

---

## 2. Where this app stands against that

| Bimi Boo | Here | |
| --- | --- | --- |
| Guided outline colouring | **Built** — Phase 1, with snap-to-line and checkpoints | ✅ |
| Kaleidoscopic mirror | **Designed, not built** — `effectiveSymmetryAxis` on every asset | 🟡 |
| Colour by number | **Designed, not built** — `regions[].number`, `supportsNumbers` | 🟡 |
| Freeform sketching | **Not built**, and currently ruled out by the README | ❌ |
| Neon-glitter magic | **Not built** | ❌ |
| Pixel art | **Not built** | ❌ |
| Finished picture animates | **Not built** — the biggest gap | ❌ |
| Patterns: stars, rainbows, glitter | **Not built** | ❌ |
| 170+ pictures | **10** | ❌ |

Two honest observations before the feature list.

**The trace guide is ahead of the target.** Snap-to-line with a quadratic
falloff, checkpoints tested along the whole travelled segment, finishing at 85%
— that is a more careful tracing interface than "a tracing interface for easy
drawing" implies. Phase 1 does not need revisiting to match Bimi Boo.

**Content volume is the real gap, and the art tool is the answer to it.** 10
against 170+ is not a feature deficit, it is a content deficit, and no amount
of modes closes it. The PNG trace tool already built is the lever: it turns a
drawing into an asset in minutes, and it is something a subscription app cannot
offer at all. Expect to spend as much effort on drawings as on code.

---

## 3. What this target changes about the existing design rules

The README currently says free drawing with no guide is deliberately not done.
**Aiming at Bimi Boo reverses that** — "freeform sketching" is one of its
headline modes, and glow, glitter and kaleidoscope brushes are all at their best
on a blank page. See F4.

Everything else survives unchanged: zero reading, no fail states, landscape,
offline, no accounts. Bimi Boo is aimed at 2–6 and is also wordless, so the
constraint is if anything reinforced.

---

## 4. Features

Ordered by how much of the target they close. Each states what is already in
place, because that is what separates a week from an afternoon.

---

### F1. The finished picture comes to life ⭐ *the headline*

**What.** When a drawing is finished, it plays a short cartoon of itself —
the parts move, with sound.

**Why first.** It is the single feature that most defines the target, and it is
the payoff loop: every other mode ends here. It is also what a child describes
to someone else afterwards.

**The problem.** Hand-animating 170 pictures does not scale, and would make
every new drawing cost an animator.

**The way round it, and why this app can.** The assets are not flat images —
every drawing is a **list of named vector regions with interior points**, built
for colour-by-number. That is enough to animate generically: a region can be
bounced, rotated about its own centre, squashed, or blinked without anyone
authoring a timeline. A head that nods, legs that walk in alternation, a tail
that sways. Pick the motion per region by a tag (`head`, `limb`, `tail`,
`eye`), and default to a gentle whole-body breathe for anything untagged.

**So the authoring cost is one optional tag per region**, and an untagged
drawing still animates — the same bargain the asset format already makes with
`number` and `symmetryAxis`.

**Already in place.** Named regions; interior points from the widest horizontal
run; `CanvasFit`; the celebration and sound layers.

**Acceptance:**
- Every shipped drawing animates, including untagged ones
- A traced import animates with no extra work
- The child's own colours are what move — this is their picture, not a stock one
- It can be replayed, and skipped
- Nothing about it can fail or be got wrong

**Size:** L. **Risk:** medium — the risk is it looking cheap rather than not
working. Worth prototyping on one drawing before committing.

---

### F2. Neon-glitter magic

**What.** Glow and glitter brushes: a bright core with a coloured bloom, and
sparkles scattered along the stroke.

**Already in place.** `BrushKind` is an enum addressed by **key**, and strokes
store the key, so new brushes are additive and cannot strand a saved drawing.

**How it works.** Glow: draw each stroke twice — a blurred halo
(`MaskFilter.blur`) under a lighter core. `BrushKind` gains a `glow` field;
existing brushes get zero and are unchanged. Glitter: deterministic scatter
seeded from the stroke id, so reopening a drawing reproduces the sparkles
exactly rather than reshuffling them — the same reason the crayon's wobble is a
function of position and not a random number.

**Needs F3** to look right: glow on a near-white canvas is a smudge.

**Acceptance:** the existing three brushes are pixel-identical to before; a
saved glow drawing reopens unchanged; no frame-rate drop under a moving finger
— blur is the one effect here that can cost real time, so this gets checked on
the tablet rather than assumed.

**Size:** M. **Risk:** medium, entirely performance.

---

### F3. Dark canvas

**What.** A dark background for the modes where glow belongs.

**Why it is a feature and not a toggle.** It is what makes F2 worth building.
The complication is that this app's line art is dark-on-light, so a dark canvas
is straightforward for freeform sketching and awkward for outline colouring.
Recommendation: **dark is a property of the free-draw and glow modes**, not of
the picture library. See Q2.

**Size:** M. **Risk:** medium — checkpoints, region fills and the exported PNG
all currently assume a light ground.

---

### F4. Freeform sketching

**What.** A blank page with the full brush set and no guide.

**Why.** It is one of Bimi Boo's named modes, it is where the glow and glitter
brushes actually live, and it is the mode with no content cost at all — it
needs no drawings.

**This reverses a stated non-goal**, so it is worth agreeing deliberately rather
than slipping in.

**Already in place.** The whole canvas, stroke, undo and gallery stack is
guide-agnostic; the trace guide is what gets switched off.

**Size:** S — genuinely, most of this is already built.
**Risk:** low.

---

### F5. Kaleidoscopic mirror (Phase 2)

**What.** Strokes mirror across an axis. Bimi Boo calls it kaleidoscopic, which
implies more than two-fold — 4- and 6-fold radial symmetry makes
kaleidoscope patterns rather than only butterflies.

**Already in place.** `effectiveSymmetryAxis` on every asset, falling back to a
line down the middle, so every drawing is already mirror-drawable.

**How it works.** Each committed stroke drawn N times, reflected or rotated at
paint time from one stored stroke — not stored N times, or undo removes a
quarter of a butterfly.

**Acceptance:** undo removes all copies of a stroke as one action; 2-, 4- and
6-fold all work; a saved mirror drawing reopens whole; works on an asset with
no authored axis.

**Size:** M. **Risk:** low — the geometry is pure Dart and testable without a
device.

---

### F6. Colour by number (Phase 3)

**What.** Numbered regions, numbered palette, tap to match.

**Already in place.** `regions[].number`, `suggestedColor`, `supportsNumbers`,
and the per-region interior point — which is exactly where a number goes, and
which is already correct for ring-shaped regions where a bounding-box centre
would land in the hole.

**Blocked on F7:** none of the ten shipped drawings are numbered.

**Acceptance:** only `supportsNumbers` assets offer the mode; numbers sit inside
their region on every shipped drawing, asserted by a test rather than by eye; a
wrong tap is silent and harmless.

**Size:** M. **Risk:** low.

---

### F7. Number the shipped art

Extend `tool/generate_art.py` to assign numbers, with a test that every shipped
asset reports `supportsNumbers`. **Size:** S. Unblocks F6.

---

### F8. More pictures

**What.** Get from 10 towards 170+, across more topics — Bimi Boo ships
animals, dinosaurs, cars, dolls, school things. This app has dinosaurs and farm.

**How.** Both routes already exist: `tool/generate_art.py` for generated art,
and the PNG trace tool for hand-drawn art. The tool is the faster of the two
for anything with character.

**This is the biggest single lever on whether the app feels like the target**,
and it is the one that is not a coding task.

**Size:** L, ongoing. **Risk:** low, but it is real work.

---

### F9. Choosing a mode, without words

**What.** Six modes need a wordless picture language: a dashed outline for
trace, a butterfly for mirror, a numbered swatch for numbers, a glowing
squiggle for neon, a blank page for freeform.

**Why listed separately.** It is the feature most likely to be under-thought and
the one that most easily breaks the zero-reading rule. It is a design problem,
not a coding one.

**Size:** M. **Risk:** medium.

---

### F10. Patterns and stamps

**What.** Tap to drop a star, rainbow, heart or glitter burst — Bimi Boo's
"colorful patterns & templates".

**How.** A new action kind in the artwork history, so it undoes like everything
else. Art generated in the existing visual language rather than sourced, for the
same reason the sounds are synthesised.

**Size:** M. **Risk:** low.

---

### F11. Pixel art mode

Bimi Boo's newest mode: colour a grid cell by cell. Listed for completeness —
it shares nothing with this app's vector pipeline and would need its own asset
type, its own authoring and its own renderer. **Recommendation: skip unless you
specifically want it.** **Size:** L.

---

### F12. Housekeeping

- **C1.** Numbering flow in the art tool — `supportsNumbers` is all-or-nothing,
  so one unnumbered region makes a drawing invisible to F6 with nothing saying
  why. Show "numbered 7 of 9". **S**
- **C2.** Re-open a traced drawing to edit it, rather than delete and re-trace. **M**
- **C3.** Confirm the v1.0.3 PNG-trace fix on the tablet. Diagnosed by reading,
  not reproducing. **S**

---

## 5. Suggested order

**First, prove the payoff.** F1 on a single drawing, as a prototype. It is the
feature that defines the target and the one most likely to disappoint; knowing
early whether generic region animation looks charming or cheap decides whether
the rest of the plan is right.

Then:

1. **F4** freeform sketching — small, and the home for everything in step 2
2. **F2 + F3** neon-glitter and the dark canvas
3. **F1** the cartoon, properly, if the prototype earned it
4. **F7 → F6** numbers
5. **F5** mirror and kaleidoscope
6. **F9** mode selection — once there are enough modes to need it
7. **F10** patterns and stamps
8. **F8** more pictures, continuously throughout

F8 runs alongside everything. Modes multiply the value of pictures; pictures do
not multiply the value of modes.

---

## 6. Open questions

**Q1 — Does F1 earn its place?** It is the largest item here and the one that
defines the target. Prototype first, or commit now?

**Q2 — Dark canvas scope.** Free-draw and glow only, or do some picture
drawings get a night version too? The latter means light and dark line art for
every drawing.

**Q3 — Freeform sketching.** Confirm the README's "no free drawing" non-goal is
being reversed deliberately.

**Q4 — How many brushes?** Three today, on purpose. Bimi Boo is closer to a
dozen. Suggestion: six — pencil, crayon, marker, glow, glitter, rainbow.

**Q5 — Age.** Bimi Boo targets 2–6; this app is written for 5–8. The gap shows
in the trace guide's difficulty and the 85% completion rule. Stay at 5–8, or
widen down?

**Q6 — Animation tags.** Does the art tool gain a region tag picker
(`head`/`limb`/`tail`/`eye`) for F1, or does everything rely on the untagged
default?

---

## 7. Explicitly out of scope

Unchanged, and restated so none of the above quietly erodes it:

- Accounts, network, ads, in-app purchases, subscriptions — the app never talks
  to anything. Bimi Boo is subscription-funded; this is not.
- A cloud gallery. Saved work is on the tablet.
- Anything scored, timed, or marked wrong.
- Text anywhere outside the grown-up gate.
- Draw-on-a-photo: permissions, arbitrary images in front of a child, and a
  bitmap inside a storage format that is deliberately vector-only.

---

## Sources

- [Bimi Boo — Drawing](https://bimiboo.net/apps/drawing/) · [Drawing Pages for Kids](https://bimiboo.net/apps/drawing-pages-for-kids/)
- [Coloring for Kids: Drawing 2-6 — Google Play](https://play.google.com/store/apps/details?id=com.bimiboo.kids.drawing&hl=en_US) — the mode list, the cartoon, pixel art and colour-by-number
- [Kids Coloring. Drawing Games — App Store](https://apps.apple.com/us/app/kids-coloring-drawing-games/id6444398254)
- [Kids Doodle — Paint & Draw](https://play.google.com/store/apps/details?id=com.doodlejoy.studio.kidsdoojoy&hl=en&gl=US) — 24 brushes including glow, neon, rainbow, fireworks
- [Drawing For Kids — Glow Draw](https://play.google.com/store/apps/details?id=kids.doodledraw.best.photo.apps&hl=en_US&gl=US) — neon on black, stickers
