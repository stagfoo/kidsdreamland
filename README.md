# King Kids Dream Land

A trace-and-colour drawing app for a five-to-eight-year-old on an Android
tablet. Pick a category, pick an animal, trace the dashed line or fill the
regions, and the finished picture goes in a gallery.

**Zero reading required.** There is no text anywhere in the app — not a
title, not a button label, not an error. The audience cannot read, and a
screen that has to be explained by an adult is a screen the child needs an
adult for. Everything is a picture, a colour or a sound.

**No fail states.** Nothing is scored, timed or marked wrong. The trace
guide is forgiving by design; the finish button is available from the first
second, not unlocked by completing anything; a tap on the wrong thing does
nothing rather than saying so.

Landscape only: a drawing is wider than it is tall, and the tool column
needs the width.

## Phases

This is **Phase 1** of three. Each phase is mostly new interaction logic on
top of the same rendering, asset and feel infrastructure.

| | Status |
| --- | --- |
| **Phase 1 — Trace & Colour** | Built |
| **Phase 2 — Mirror drawing** | Not started; the asset schema and `effectiveSymmetryAxis` are already in place |
| **Phase 3 — Paint by numbers** | Not started; `regions[].number` parses and `supportsNumbers` reports it |

## Drawing

The canvas is the whole screen between the two control edges.

- **Pencil, crayon and marker** differ in width, opacity and grain rather
  than in what they can do — a child picks by feel, not by capability. The
  crayon's width wobbles along its length, which is what stops it looking
  like a fat marker.
- **The bucket** fills a region on tap, and keeps filling as you drag
  across regions, which is how it actually gets used.
- **The eraser** removes whole strokes it touches. It cannot damage the
  line art or a region boundary — there is nothing a child can do here
  that breaks the drawing they were given.
- **Undo** is the largest control on the screen after the canvas. It is the
  most-used button at this age by a wide margin, and a child who cannot
  find it stops drawing rather than asking. Strokes, fills and erasures
  share one history, so undo always means "the last thing I did".

### Snap-to-line

A five-year-old's line wanders. `snapToOutline` pulls a drawn point towards
the line art with a quadratic falloff: strong correction close in, easing
to nothing at the 46-unit tolerance edge. Fully snapping would make the
line feel magnetic rather than theirs; not snapping at all makes a wobbly
trace look like a scribble. The falloff is tested for monotonicity, because
a correction that ever pulls harder further out makes the line jitter
backwards under a steadily moving finger.

Checkpoints are tested along the **whole travelled segment**, not at the
sampled touch positions. A fast drag delivers events a long way apart, and
by-point testing skips every dot the finger flew over — which reads as the
app not noticing you did the easy part. Order never matters: starting at
the tail is as valid as starting at the nose.

A drawing counts as finished at **85%** of its checkpoints, not 100%.
Insisting on every last dot turns a finished picture into a hunt for the
one behind the tail.

## The asset format

One JSON file per drawing serves all three modes, so each image is authored
once. `assets/art/index.json` lists them and states category order.

```json
{
  "id": "dino_trex",
  "category": "dinosaurs",
  "canvas": { "width": 1024, "height": 1024 },
  "outline": "M120,340 C160,300...",
  "guideDots": [ {"x":120,"y":340} ],
  "regions": [
    { "id": "body", "path": "M130,350 L...", "number": 3,
      "suggestedColor": "#8BC34A" }
  ],
  "symmetryAxis": { "type": "vertical", "x": 512 }
}
```

| Mode | Uses | Ignores |
| --- | --- | --- |
| Trace | `outline`, `guideDots`, `regions[].path` | `symmetryAxis`, `number` |
| Mirror | `symmetryAxis` (or centre-vertical) | `regions`, `number` |
| Numbers | `regions[].number`, `suggestedColor` | `guideDots` |

**`number` and `symmetryAxis` are optional**, deliberately: art production
stays ahead of mode development rather than gold-plating assets for phases
that do not exist. An asset drawn today is trace-ready now and gains its
numbers whenever Phase 3 arrives. `supportsNumbers` reports whether an
asset has been given a full set, and `effectiveSymmetryAxis` falls back to
a vertical line down the middle, so **every** asset is mirror-drawable
whether or not anyone thought about it at authoring time.

`guideDots` is optional too. Unauthored, checkpoints are spaced evenly
**along the outline by arc length** — not by vertex index, which would
bunch them up on the curves, exactly where the drawing is fiddliest.

**Difficulty is derived, not authored** — from region count and outline
length, so it can never drift out of step with the drawing it describes,
and adding an image is one file with no bookkeeping. It shows on a card as
one, two or three dots; dots rather than a number, because a number is a
thing to read and a thing to be graded by.

### Authoring

`tool/generate_art.py` builds the ten shipped drawings from primitives
(ellipse, polygon, rounded rect, zig-zag ridge). Ten animals of hand-written
bezier data is ten chances to typo a coordinate into a shape nobody notices
is wrong until a child is looking at it, and the whole set has to share one
visual language or the trace guide is followable on some drawings and not
others.

Parts are listed big-to-small. `Artwork.regionAt` searches last-first, so
that ordering is also what makes a tap on an eye hit the eye rather than
the head behind it.

`test/art_assets_test.dart` runs against the real files and is the guard
that stops a bad shape reaching a tablet: every region must have a tappable
interior, be big enough for a fingertip, and have a unique id; every guide
dot must sit on the outline; the drawing must fill a decent share of its
canvas and stay inside it.

## The feel layer

### Squishy buttons

`SquishyButton` wraps every tappable thing in the app — category tiles,
swatches, tool icons, the finish button. One wrapper rather than per-widget
animations, because they would drift apart in feel immediately.

Scale to 0.90 on touch-down, then an `elasticOut` spring back through an
overshoot to 1.0. The drop shadow shrinks and tightens as the button sinks,
so it reads as moving towards the page rather than just getting smaller.

It listens on `Listener`, not `GestureDetector`: a press has to squash the
instant a finger lands, with no wait to see whether the gesture arena is
about to hand the touch to a scroll instead. On a tile inside a scrolling
grid that delay is clearly visible.

### Sound

One sonic palette — soft marimba and bells — **synthesised**, not sourced,
by `tool/generate_sounds.py`. A bag of free downloads does not share a
timbre, and a synthesised set can be retuned by changing a number rather
than by finding new samples. Seven effects, 22kHz mono, 100KB total.

Every decision about *whether* to play lives in `SoundPolicy`, which is
pure and tested at full speed against an injected clock and RNG:

- **Throttling per effect.** `draw` loops under a dragging finger, which
  delivers events every few milliseconds; `complete` is throttled hard
  because two celebrations on top of each other sound like a mistake.
- **Pitch jitter** of a few percent on the repeated effects, symmetric
  around 1.0 so a long run averages out at the sample's own pitch instead
  of drifting sharp. The celebration gets none — it should sound the same
  every time it is earned.
- **The palette rings a rising fifth** across its six colours, so the
  colours have an order you can hear.
- **Mute** clears the throttle history, so unmuting responds to the very
  next tap instead of swallowing it.

`SoundManager` holds a round-robin pool of six players. One player per
effect would cut a sound off when it retriggers; one overall would cut
*every* sound off, and a fill landing on top of a draw scratch is normal.
Audio failure is swallowed — a device with no working audio route still
gets a drawing app.

## Layout

Everything worth being sure about is plain Dart with no Flutter or plugin
imports, so it is testable with no device attached.

| File | Does |
| --- | --- |
| `lib/geometry.dart` | `Vec2`, `Bounds`, point-to-segment, point-in-polygon, arc-length sampling |
| `lib/svg_path.dart` | SVG path data to commands and flattened polylines |
| `lib/drawing_asset.dart` | The asset schema and its parsing |
| `lib/trace_guide.dart` | Snap-to-line and checkpoint progress |
| `lib/artwork.dart` | Strokes, fills, erasure, undo, serialisation |
| `lib/stroke.dart` | Stroke model, spacing, brush grain |
| `lib/palette.dart` | The six colours and three brushes, by key |
| `lib/canvas_fit.dart` | Asset units to screen and back |
| `lib/sound_policy.dart` | Throttling and pitch, with no audio in sight |
| `lib/artwork_painter.dart`, `lib/mascot.dart`, `lib/*_screen.dart`, `lib/squishy_button.dart`, `lib/palette_strip.dart`, `lib/tool_picker.dart`, `lib/celebration.dart` | The UI |
| `lib/sound_manager.dart`, `lib/asset_library.dart`, `lib/gallery_store.dart` | The thin layer that touches plugins |

Colours and brushes are stored as **keys**, not raw values, so retuning the
palette restyles saved work rather than stranding it, and a drawing written
by a future build with a colour this one does not know still opens. An
unknown action kind in a saved file is skipped rather than fatal, for the
same reason.

### Keeping the canvas fast

Completed work sits behind a `RepaintBoundary` with its own painter, and
the stroke currently under the finger is a second painter on top. A moving
finger repaints one stroke rather than an afternoon of them — repainting
everything on every touch event is what makes a drawing app go sludgy
twenty minutes in, which is exactly when a child is most invested.

`ArtworkPainter` takes a `revision` counter rather than deep-comparing a
stroke list, which is both cheaper and more honest about what changed.

## The gallery

Each finished piece is a PNG plus the artwork JSON beside it. The JSON
means a drawing can be reopened and added to; the PNG means the gallery
draws instantly rather than re-rendering ten drawings to show ten
thumbnails. Saved pieces are keyed by asset id **plus a timestamp** — a
child colouring the same T-Rex twice has made two drawings, not overwritten
one.

The exported PNG is rendered off the widget tree, so it is exactly the
drawing and not whatever chrome was on screen, and it is painted onto an
opaque background: transparency reads as black in most photo viewers, which
would make every drawing look ruined.

Export to the device's own photo gallery uses `gal`, and returns false
rather than throwing when permission is refused — a child tapping export
and getting a crash is far worse than one tapping export and seeing
nothing happen.

## Building

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

`android/app/debug.keystore` is committed on purpose (debug-only, never
used for release signing) so local and CI builds share one signing identity
and can install over each other. Verify it rather than assuming — note that
`keytool -printcert -jarfile` only understands legacy v1 JAR signing and
will wrongly call a modern APK unsigned:

```sh
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
keytool -list -v -keystore android/app/debug.keystore -storepass android \
  -alias androiddebugkey
```

`flutter analyze` and `flutter test` never touch Gradle, so a broken
release config sits invisible until someone actually builds one — worth
doing after any change to the Android side, not just before shipping.
`android/app/proguard-rules.pro` keeps the reflective entry points for
`audioplayers` and `gal`.

Regenerating art or sound:

```sh
python3 tool/generate_art.py      # assets/art/*.json
python3 tool/generate_sounds.py   # assets/sounds/*.wav  (needs numpy)
```

## Installing with Obtainium

[Obtainium](https://github.com/ImranR98/Obtainium) tracks the GitHub
releases and installs updates, which beats downloading an APK by hand every
time.

**Add it:** paste `https://github.com/stagfoo/kidsdreamland` into
Obtainium's Add App screen. No extra settings are needed, because releases
are shaped to Obtainium's defaults:

- **The tag is exactly the version** — `1.0.1`, not `v1.0.1-3d1885e`.
  Obtainium compares the version a release advertises against the version
  Android reports for the installed app, and can only do that when the two
  are the same shape. A tag carrying a `v` and a commit sha would need a
  `versionExtractionRegEx` set by hand.
- **Every release bumps the version and the build number.** Shipping the
  same version twice leaves Obtainium nothing to compare and Android no
  reason to treat the APK as an update.
- **One APK asset per release**, so no `apkFilterRegEx` is needed.

The repo is public so that this needs no token. While a repo is private,
GitHub's API answers anonymous requests with a 404 rather than a 403 — it
hides private repos rather than admitting they exist — and Obtainium
surfaces that as "Could not find a suitable release", which reads like a
problem with the releases rather than with access to them.

Publish only ever through `scripts/release.sh`, never by hand: it bumps the
version, commits, pushes, and verifies with `aapt2` that the APK it is
about to upload actually carries the new version. Releasing a stale
artifact ships the previous version under a new tag, Android sees an
unchanged versionCode and declines the install, and the release quietly
contains none of its own changes.

`android/app/debug.keystore` is public along with everything else. It is a
debug-only key with the standard `android` password, which does mean the
signature on these APKs is not a secret: anyone could sign an APK that
Android would accept as an update. They would still have to get it onto the
tablet, and nothing here is distributed through a store, so the exposure is
small — but it is the reason to think twice before reusing this pattern for
anything that matters.

## What it deliberately doesn't do

- **Accounts, network, ads, in-app anything.** The app never talks to
  anything.
- **A cloud gallery.** Saved work is on the tablet.
- **Free drawing with no guide.** That is Phase 2's mirror mode, which is
  freeform by design.
