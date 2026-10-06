# King Kids Dream Land — feature PRD

**Status:** draft for review. Nothing here is built yet unless it says so.
**Date:** 2026-10-06
**Against:** v1.0.4

This is a menu, not a plan of record. Strike out what you do not want, reorder
what you do, and answer the open questions at the bottom — several features
change shape depending on those answers.

---

## 1. What this app is

A trace-and-colour drawing app for a five-to-eight-year-old on an Android
tablet, used offline, with no accounts and no network.

Every feature below has to survive four constraints that are not up for
negotiation, because they are what makes the app usable by its audience:

| Constraint | What it rules out |
| --- | --- |
| **Zero reading** | No labels, no menu text, no written errors. A feature that needs a word is a feature that needs an adult. |
| **No fail states** | Nothing scored, timed, locked or marked wrong. No "unlocked by". |
| **Landscape only** | No layout that wants height. |
| **Offline, no accounts** | No sharing to anything, no cloud, no sign-in. |

The one exception is the art tool behind the grown-up gate, which is text and
is for you, not for the child.

---

## 2. Where the app is today

**Built and shipped:**

- Phase 1 — trace and colour: pencil/crayon/marker, bucket fill, eraser, undo,
  snap-to-line, checkpoint progress, finish at 85%
- 10 drawings across 2 categories (dinosaurs, farm), difficulty derived from
  the art rather than authored
- Gallery: PNG plus re-openable JSON, export to the device photo gallery
- The art tool: trace a transparent PNG into a drawing, four sliders, region
  naming/colouring/numbering, import and export packs (v1.0.2)
- A copyable log behind the gate (v1.0.4)

**Designed for but not built** — the hooks exist and are tested:

- `effectiveSymmetryAxis` on every asset, falling back to a line down the
  middle, so *every* drawing is already mirror-drawable
- `regions[].number` parses, and `supportsNumbers` reports whether an asset has
  a full set
- `BrushKind` is an enum keyed by string, and strokes store the **key** — so a
  new brush is additive, and old saved drawings keep opening

---

## 3. Features

Each one states what is already in place, because that is what separates a
week from an afternoon.

### Group A — the two planned phases

These were designed into the asset format from the start. Everything else in
this document is optional; these are the backbone.

---

#### A1. Mirror drawing (Phase 2)

**What.** The child draws on one side of the canvas and the same stroke appears
mirrored on the other. Butterflies, faces, masks.

**Why it fits.** It is freeform — no outline to follow, no checkpoints, nothing
to complete — so it answers "I want to just draw" without adding a blank page,
which at this age is more intimidating than a guide.

**Already in place.** `effectiveSymmetryAxis` on every asset including the ten
shipped ones. `ArtDraft.symmetryAxisX` is authored by the art tool.

**How it works.** Each committed stroke is drawn twice, the second reflected
through the axis. Reflection happens at paint time from one stored stroke, not
by storing two — otherwise undo removes half a butterfly.

**Acceptance:**
- Drawing on either side mirrors to the other
- Undo removes both halves of one stroke as a single action
- Fill and eraser mirror too, or are hidden in this mode — see open question Q2
- A saved mirror drawing reopens with both halves intact
- Works on an asset that has no authored axis (falls back to centre)

**Size:** M. **Risk:** low — the geometry is already there and testable without
a device.

---

#### A2. Paint by numbers (Phase 3)

**What.** Each region shows a number; the palette shows the same numbers; tap a
colour then tap matching regions.

**Why it fits.** It is the mode that teaches colour-matching, and it is the one
most likely to hold attention unsupervised, because it has a built-in
"what next" that trace mode does not.

**Already in place.** `regions[].number`, `suggestedColor`, `supportsNumbers`,
and the per-region **interior point** taken from the widest horizontal run —
which the README already names as where the number goes. That point matters:
for a ring-shaped region a bounding-box centre lands in the hole.

**How it works.** Numbers drawn at the interior point. The palette strip shows
numbered swatches instead of plain ones. A correct tap fills; a wrong tap does
nothing (no fail state, no buzz).

**Acceptance:**
- Only assets where `supportsNumbers` is true offer this mode
- Numbers sit inside their region on every shipped drawing — a test, not an eye
- A wrong tap is silent and harmless
- Finishing is "all regions filled", celebrated the same way as a trace

**Blocked on:** A3 — none of the ten shipped drawings are numbered yet.

**Size:** M. **Risk:** low mechanically; the real cost is A3.

---

#### A3. Numbering the shipped art

**What.** Give the ten shipped drawings a full set of numbers so A2 has
anything to run on.

**How.** Extend `tool/generate_art.py` to assign numbers, since the art is
generated from primitives rather than hand-authored. A test asserts every
shipped asset has `supportsNumbers` true.

**Size:** S. **Risk:** low, but A2 is dead without it.

---

#### A4. Choosing a mode

**What.** Once there are three modes, the child has to pick one — without
words.

**Why it is listed separately.** It is the feature most likely to be
under-thought and most likely to break the zero-reading rule. Three modes
behind one card needs a picture language: a dashed outline for trace, a
butterfly for mirror, a numbered swatch for numbers.

**Open:** whether the mode is picked before opening a drawing or switched
inside it. See Q1.

**Size:** M. **Risk:** medium — this is a design problem, not a coding one.

---

### Group B — brushes and canvas

Researched against what popular kids' drawing apps actually ship. The common
set across Kids Doodle, Glow Draw, Neon Doodle and Joydoodle is: **glow/neon,
rainbow, sparkle/fireworks, stamps, and a dark canvas to put them on.**

The architecture makes most of these cheap: `BrushKind` is an enum, strokes
store the brush **key**, so adding brushes is additive and never strands a
saved drawing.

---

#### B1. Glow brush ⭐ *best effort-to-delight ratio*

**What.** A neon stroke that blooms — bright core, coloured halo.

**How it works.** Draw each stroke twice: once with
`MaskFilter.blur(BlurStyle.normal, sigma)` in the stroke colour for the halo,
then the core on top in a lighter tint. `BrushKind` gains a `glow` field; every
existing brush gets zero and behaves exactly as now.

**Acceptance:**
- A glow stroke blooms; the other three brushes are pixel-identical to before
- Saved and reopened intact; a build that does not know the key still opens the
  drawing (already guaranteed by key-based storage)
- No frame-rate drop while drawing — blur is the one effect that can cost real
  time, so this needs checking on the tablet, not asserted

**Depends on:** B4 to look right. Glow on a near-white canvas looks like a
smudge.

**Size:** S. **Risk:** medium — purely the performance of a blurred repaint
under a moving finger.

---

#### B2. Rainbow brush

**What.** The colour travels through the palette along the length of the
stroke.

**How it works.** Strokes are already a spaced polyline; colour each segment by
its index. No new storage: the brush key says "rainbow" and the colour is
derived at paint time, so it restyles if the palette is ever retuned — the same
property the app already relies on for saved work.

**Acceptance:** one continuous drag passes through the palette; a short tap is
still a visible dot.

**Size:** S. **Risk:** low.

---

#### B3. Sparkle brush

**What.** Stars and dots scatter along the stroke.

**How it works.** Deterministic scatter seeded from the stroke id, so a reopened
drawing has the sparkles in the same places rather than reshuffling — the same
reason the crayon's wobble is a function of position rather than a random
number.

**Acceptance:** reopening a saved drawing reproduces it exactly.

**Size:** M. **Risk:** low.

---

#### B4. Dark canvas / night mode

**What.** A per-drawing dark background, so glow and sparkle read.

**Why it is a feature and not a setting.** Glow on white is a smudge. This is
what makes B1 and B3 worth building, and it is a real question for a
trace-and-colour app whose line art is dark on light — see Q3.

**Size:** M. **Risk:** medium — the line art, checkpoints and region fills all
assume a light ground, and the exported PNG is painted opaque on purpose.

---

#### B5. Stamps

**What.** Tap to drop a picture — star, heart, dinosaur footprint, sun.

**Why it fits.** It is the one feature in the researched set that needs no
drawing skill at all, which makes it the one a younger sibling can use.

**How it works.** A new action kind in the artwork history, so it undoes like
everything else. Art generated by `tool/generate_art.py` in the existing visual
language rather than sourced, for the same reason the sounds are synthesised.

**Acceptance:** stamps undo in the same history as strokes and fills; they
export in the PNG; they cannot cover the finish control.

**Size:** M. **Risk:** low.

---

#### B6. Draw on a photo

**What.** Use a tablet photo as the canvas.

**Listed for completeness, and recommended against.** It needs camera or
gallery permission, puts arbitrary images in front of a child, and makes the
saved-drawing format carry a bitmap it currently never needs. The app's whole
storage story is "vector paths and a PNG of the result". Say if you want it
anyway.

**Size:** L. **Risk:** high.

---

### Group C — authoring and housekeeping

---

#### C1. Numbering flow in the art tool

**What.** Make it quick to number every region of a traced drawing, and show
whether the set is complete.

**Why.** `supportsNumbers` is all-or-nothing: one unnumbered region and the
drawing is invisible to Phase 3, with nothing on screen saying why.

**Acceptance:** the tool shows "numbered 7 of 9" and refuses to claim
number-readiness until it is a full set.

**Size:** S. **Depends on:** A2 being wanted at all.

---

#### C2. Re-open a traced drawing to edit it

**What.** Today a traced drawing can be deleted and re-traced, but not edited —
so fixing one region's colour means doing the whole trace again.

**Size:** M. **Risk:** low.

---

#### C3. Confirm the PNG trace fix on the tablet

**Not a feature — an open thread.** v1.0.3 moved the trace off the UI thread
after it froze the editor. That was diagnosed by reading, not by reproducing.
Worth closing before building on the art tool.

**Size:** S.

---

## 4. Suggested order

1. **A3** numbering the shipped art — small, and unblocks A2
2. **B1 + B2** glow and rainbow brushes — the cheapest visible delight, and
   they exercise the brush extension point once for both
3. **B4** dark canvas — makes B1 worth having
4. **A1** mirror drawing — the planned Phase 2
5. **A2 + A4** numbers and mode selection — the planned Phase 3
6. **B3, B5** sparkle and stamps
7. **C1, C2** authoring follow-ups

The reasoning: Group B is small and immediately visible on a tablet, where
Group A is the larger structural work. Doing one cheap visible thing first also
proves the brush extension point before three features depend on it.

---

## 5. Open questions

These change what gets built, so they are worth answering before anything
starts.

**Q1 — Mode selection.** Does the child pick trace / mirror / numbers *before*
opening a drawing (three cards per animal) or *inside* it (a switch on the tool
column)? Inside is fewer taps; before is simpler to make wordless.

**Q2 — Mirror mode's tools.** Does the bucket and eraser work in mirror mode, or
is it strokes only? Strokes only is simpler and arguably truer to what mirror
drawing is for.

**Q3 — Dark canvas scope.** Is the dark background a property of a *drawing*
(some animals are night-time), a *mode* (free-draw is always dark), or a global
toggle? This decides whether the ten shipped drawings need light and dark
variants of their line art.

**Q4 — Free drawing.** The README currently says free drawing with no guide is
deliberately not done. Glow, rainbow and sparkle are at their best on a blank
page. Does a blank-page mode get added, or do the new brushes only ever apply
on top of line art?

**Q5 — How much is too much?** Kids Doodle ships 24 brushes. This app ships
three, on purpose — a child picks by feel, and a long tool column is a thing to
read. What is the ceiling? My suggestion is six: the existing three plus glow,
rainbow and sparkle.

---

## 6. Explicitly out of scope

Unchanged from the README, and worth restating so none of the above quietly
erodes it:

- Accounts, network, ads, in-app purchases — the app never talks to anything
- A cloud gallery — saved work is on the tablet
- Anything scored, timed, or marked wrong
- Text anywhere outside the grown-up gate
- Multiplayer or shared drawing, which several of the researched apps ship and
  which would need a network

---

## Sources

Feature research, October 2026:

- [Kids Doodle — Paint & Draw](https://play.google.com/store/apps/details?id=com.doodlejoy.studio.kidsdoojoy&hl=en&gl=US) — 24 brushes including glow, neon, rainbow, fireworks, spark, ribbon
- [Drawing For Kids — Glow Draw](https://play.google.com/store/apps/details?id=kids.doodledraw.best.photo.apps&hl=en_US&gl=US) — neon and glow paint on a black background, stickers
- [Neon Doodle Art Paint for Kids](https://play.google.com/store/apps/details?id=com.doodle.best.glow.paint&hl=en_US) — neon glow effect as the central mechanic
- [Drawing Games: Draw & Color](https://play.google.com/store/apps/details?id=com.rvappstudios.kids.drawing.games.coloring.book.paint&hl=en_US)
- [14+ Best Drawing Apps for Kids — Adobe](https://aqua.adobe.com/learn/drawing-apps-for-kids)
- [8 Best iPad & Android Tablet Drawing Apps for Kids in 2026](https://famisafe.wondershare.com/app-review/drawing-apps-for-kids.html)
