# combo.json — the event timeline

Each combo lives in `combos/<name>/` of a Godot project: `<name>.tscn` (a `ComboPlayer` node
whose `combo_file` and `style_file` point at the two JSON files), `combo.json`, `style.json`
and `prompt.md`. `tools/new_combo.py` writes all of them.

A combo is a list of timed events. The demo fires each event when the combo clock reaches
its `t`; during a hit-stop the clock (and everything on screen except the target's shudder)
stops, so `t` is "combo time", not wall time.

```json
{
  "name": "free text, shown nowhere",
  "events": [
    {"t": 0.00, "do": "slash", "radius": 160, "from": -70, "to": 70, "width": 44},
    {"t": 0.04, "do": "hit", "push": 60, "stop": 0.05, "shake": 2.5, "spark": 46}
  ]
}
```

Events may be in any order (they are sorted by `t`). Any field marked *default* may be left
out.

## The stage

Screen 1280 × 720, y grows downward, the attacker faces right.

| Thing | Position |
|---|---|
| ground line | y = 520 |
| attacker (diamond marker) start | (430, 450) — 70 px above the ground |
| target (block, 44 × 96) start | feet at (575, 520); its centre is ~145 px right of and ~20 px below the attacker |

The camera starts at the full-stage view. `camera` events can ease it closer and back;
the existing screen shake offsets that view.

## Angles

Slash angles are in degrees around the attacker: **0° points right at the target**, −90° is
straight up, +90° straight down. `from` → `to` is the direction of the swing:
`from: -70, to: 70` swings top to bottom, `from: 90, to: -90` swings bottom to top.

## Events

### `slash` — a crescent smear grown from the attacker
| Field | Meaning | Default |
|---|---|---|
| `radius` | reach in px; must be ≥ ~150 to cross the target from the start position (less after a `move` toward it) | 140 |
| `from`, `to` | start and end angle of the swing (see above); any values, so 90 → 270 sweeps behind the attacker and −90 → 270 is a full circle | −70, 70 |
| `width` | thickness of the crescent at its fattest, px (× `style.thickness`) | 44 |
| `squash` | vertical flattening of the swing ellipse; 1 = round arc, ~0.5 = a sideways sweep seen from the side, ~0.15–0.2 through 0° = a thrust | 1 |
| `tilt` | rotates the whole ellipse, degrees; tilts a flattened sweep into a diagonal | 0 |
| `palette` | `normal`, `violet`, `red`, `gold` or `green` (colours come from style.json) | normal |

The crescent grows in 0.045 s, holds 0.04 s and fades over 0.13 s. It is attached to the
attacker, so a `move` at the same `t` drags it along (that is what gives a lunge its weight).

#### Sampled trajectory renderer

Set `"renderer": "ribbon"` in `style.json` to use `ribbon_stage.gd` with the same
event player. `slash` accepts `duration` (swing seconds, default 0.16) and `tail`
(retained sample lifetime, default 0.18), plus the normal angle, squash, tilt, width
and palette fields. Its reach is fitted to the target's predicted contact position;
`radius` is not used by this renderer. The midpoint of `from` and `to` crosses the
target at half `duration`, so pair each slash with a `hit` at `slash.t + duration / 2`
rather than the stock crescent's fixed 0.03–0.05 s delay. Put simultaneous `move`
events before the slash so targeting can account for the movement.

This renderer grows a triangle band from blade samples, shades UV breadth and
birth time, and thins/deletes old samples. It shares the stage action clock and
checks the visible ribbon covers every hit point. `combos/rift_dancer/` is the
complete nine-hit example; `combos/trajectory_slash/` is the single-cut study.

#### Claw renderer

Set `"renderer": "claw"` in `style.json` to use `claw_stage.gd`: every `slash` becomes a
set of torn crescent gashes (needle tail, fat belly, razor tip, ragged edges) fanning out
like a paw along one path, each followed by a thin trail; only the stretch just behind
the heads shows, then the gashes erode from their tails. They are aimed so the strands cross the target at
`slash.t + duration × contact` — pair each slash with a `hit` at that time. Every hit
also scratches the target along the claw's direction (the marks ride its knockback), and
a slam finisher bites into the floor and cracks it to both sides. `combos/claw_cyclone/` is the complete example.

| Field | Meaning | Default |
|---|---|---|
| `claw` | `arc`: around the attacker using `from`/`to`/`squash`/`tilt` like a sword arc (any sweep: −90 → 270 is a full loop, more is several — 大回环; the gashes keep circling after the contact); `swipe`: 横斩, a wide shallow horizontal swipe (`angle` 0 forehand, 180 backhand, `length`, `bend`); `dash`: 突进, the attacker really lunges at the target with the claws out (stopping just short) and the gashes pierce `past` px beyond; `cross`: 交叉斩, two rakes in an X at `angle` and 180−`angle`, the second `cross_delay` s later — pair it with two hits; `rake`: a straight swipe through the target at `angle`; `slam`: 暴扣, a dive from high behind the target, through it, into the floor and a skid | arc |
| `duration`, `tail` | seconds the strands take to run the path / linger afterwards | 0.16, 0.22 |
| `contact` | fraction of `duration` at which the strands cross the target | 0.5 |
| `spiral` | `arc` only: radius grows from ×(1−spiral) to ×(1+spiral) through the sweep (negative shrinks) | 0 |
| `angle`, `length` | `rake` / `cross`: direction (degrees) and length (px); `swipe`: direction 0 or 180 and length (default 320) | 40, 230 |
| `bend` | `swipe`: how much it bows upwards, × its length (negative bows down) | 0.12 |
| `past` | `dash`: how far the gashes pierce beyond the target, px | 110 |
| `cross_delay` | `cross`: seconds between the two strokes | 0.07 |
| `mark`, `trail` | gash length along the path (px; 0 picks a natural length from the thickness — long paths are not stretched) and the seconds of travel the thin trail behind each gash covers | 0, 0.1 |
| `fingers`, `spread` | number of strands and the gap between them at their widest (px) | 3, 18 |
| `jag` | how torn the strands are, 0 clean … 1 ragged | 0.45 |
| `width` | gash thickness at its belly is `width × 0.34` px (× `style.thickness`) | 44 |

`combo.json` may also carry `"captions": [[t, "text"], ...]`, shown at the top left by this
renderer.

#### Magic renderer

Set `"renderer": "magic"` in `style.json` to use `magic_stage.gd` for off-hand spells. It
adds one event, `cast`; every other event works as usual. Magic is ranged, so this renderer
stands the caster back at x 360 and the target off at x 840. It draws at full resolution
with shaders (no pixel grain).

A spell is a **skeleton** — start, end, path, blast radius, with the speed curve and timing
as parameters — carrying a **body** dressed in **accessories** that follow the body's state.
For fire (`vfx/magic/fire/`) the body is a churning fireball that gathers at the start and
stretches into a comet with its speed; its accessories are sparks spiralling in while it
gathers, a muzzle flash at launch, a flame trail, warped air behind it (longer the faster
it flies), embers shed backwards, smoke left hanging on the path, its glow and an orange
pool of light on the ground that grows as it comes low. On landing it explodes: a flash
and light streak, a fireball that swells, lifts and burns out, a shockwave bending the air,
embers that bounce, debris, a smoke column, and at the floor flames and a scorch mark; the
target keeps burning.

For thunder (`vfx/magic/thunder/`) the body is the trunk: a jagged channel along the path
whose shape holds through the strike. It charges as a crackling orb at the start (sparks
drawn in, small arcs spitting off it and lashing out, the air darkening; from the `sky` a
storm cloud rolls in, lit from inside), sends a thin stepped leader down the path, then
strikes: the whole channel at full power with branches, pulsing through re-strikes, small
arcs crawling along it (thickest at the first stroke), its light everywhere and the screen
whiting out, leaving a faint violet afterimage. On landing: a blue-white flash, arcs
bursting out, sparks bouncing off the floor, a shockwave cracking the air, and at the floor
a branching Lichtenberg scar that glows and cools to a dark mark; the target stays
electrified (arcs over its body, white jolts).

For ice (`vfx/magic/ice/`) the body is a clear, double-pointed six-sided crystal rolling
about its long axis — the bigger, the slower — so the light slides from face to face
(bright ridges, a specular glint, fractures inside; on the 炸裂 tier the world shows bent
through it). **Ice never curves:** whatever `path` says, it flies dead straight. It
crystallises in jumps (ice dust drifting in, frost creeping over the floor) and flies
speeding up (`ease` 1.6), trailing thin wisps of cold air, glittering ice dust and streaks
of cold air. On landing clear crystals burst out and shatter, chips tumble and roll (the
small ones fastest) and settle glinting. The target is frozen: clear crystals shoot up
from under its feet round it and it cannot slide until they burst; a finisher shatters
them at once. Cast from `self` with a volley (`count`), the spears hang in a cloud behind
the caster (as wide as `spread`) until the charge is over, then loose one after another —
暴雨梨花. Staying put (`path: stay`, `start: target`), it is a ring of crystals hovering
round the target and following it, pouring heavy cold mist; while it holds the target
moves (knockback, flight, fall) at 0.3 of its speed, and at the last landing the crystals
burst outwards (`ice/halo.gd`).

For wind (`vfx/magic/wind/`) the body is a small white mass of air — soft billows churning
round a bright heart, wrapped in two spinning white swirls — squashed long the faster it
flies. Wind curves freely (default path `arc`, `ease` 0.85: it starts fast). Air spirals
in while it gathers; in flight it sheds little puffs that swell and thin, faint streaks,
a leaf or two, and dust off the floor when it skims low. On landing the puff bursts in a
ring of white billows with a swirl spinning open and air streaking out; the target is
buffeted by gusts. Staying put (`path: stay`, `start: target`), it is a tornado where the
target stands — broad white bands winding up a funnel of billowing air, its axis writhing
like a rope — that sweeps the target in and holds it up. Its force shows in its shape:
before each landing it winds up tight and stiff, at the landing it lashes (flares, shoots
taller, spins harder, whips, bursts dust off its foot), and at the last landing it blows
apart (`wind/tornado.gd`).

For sand (`vfx/magic/sand/`) the magic is light, not heaps: faint sand-gold motes shimmer
in the air round the caster; at the cast they are drawn in from all round and gather into
a point of light that draws out into a very fine thread of glittering grains
(`silk.gdshader`), two fainter threads weaving round it, that shoots out along the path
and runs the target through, holds taut `hold` s, then comes apart into drifting motes.
On landing a point of light and fine gold wires flick out of it, and a spray of
glittering motes hangs and drifts down; motes cling to the target and sift down it,
slowing it a little. Staying put (`path: stay`, `start: target`) it is a storm of dozens
of very fine, dense threads whirling round the target, drawing tight at every landing and
flying apart into motes at the last (`sand/storm.gd`).

`cast` — a spell from the caster:

| Field | Meaning | Default (fire / thunder; ice in `ice.gd`) |
|---|---|---|
| `element` | `fire`, `thunder`, `ice`, `wind` or `sand` | fire |
| `start` | `hand`; `above` the caster's head; `sky` high over the target; `behind` above and behind the target (it swoops back); `self` the caster's body; `below` under the floor beneath the target | hand |
| `end` | `target` (its body), `ground` (the floor under it: the blast sits on the floor) or `self` (around the caster: the blast goes off there) | target |
| `path` | `straight`; `arc` bowed by `arc` px; `wave` snaking `wave` px `turns` times; `spiral` corkscrewing in; `stay`: it stays at its start (riding along with it) for `travel` s and lands there | arc / straight |
| `arc`, `wave`, `turns` | the path's bow / swing / number of swings | 70, 40, 2 / 40, 30, 2 |
| `ease` | speed curve: 1 even, > 1 speeds up into the target, < 1 starts fast | 1.25 / 1 |
| `charge` | seconds the body gathers at the start before it flies | 0.22 / 0.3 |
| `travel` | flight seconds (thunder: the leader's run down the path) | 0.36 / 0.08 |
| `count`, `interval`, `spread` | a volley: `count` bodies launched `interval` s apart, fanned `spread` px | 1, 0.12, 36 / 1, 0.14, 30 |
| `radius` | the blast's reach at the end, px | 70 / 60 |
| `size` | the body's size (× `style.thickness`) | 1 |
| `hold` | thunder: seconds the strike keeps pulsing after it lands | — / 0.22 |
| `jag` | thunder: how hard the channel zigzags (0 smooth … 0.8 wild) | — / 0.28 |

**Body `i` lands at `t + charge + travel + interval × i`.** Pair one `hit` with each landing
(the manual editor's 「对齐命中」 button does it). A hit within 0.09 s of a landing plays the
element's impact and status instead of the stock star spark; hits that match no landing
stay melee hits. A `finisher` hit also flares the whole screen.
`combos/fire_fireball/`, `combos/thunder_bolt/`, `combos/ice_spear/`, `combos/wind_blade/` and `combos/sand_silk/` are complete examples.

Two skeletons get a body of their own: **thunder with `path: stay`** is a shield of arcs
around its start (start `self`, end `self`: around the caster, following it; it does no
harm while it holds and bursts out to `radius` when it lands — `thunder/shield.gd`), and
**fire from `start: below`** is a pillar of fire that erupts under the target and keeps
burning: its `count` hits land `interval` apart while it burns and it burns on `hold` s
after the last (`fire/pillar.gd`). `combos/magic_variants/` shows both.

`style.json` `"magic_quality"` picks the tier, lightest first: `"retro"` 复古 (drawn in
pixel grain at `style.pixel` with stepped light, like pixel art), `"balanced"` 均衡 (full
resolution, about a third of the particles, smaller halos; for weak machines),
`"ultimate"` 极致 (no screen-warping accessories — heat haze, shockwave refraction — and
about half the particles) or `"explosive"` 炸裂 (default: everything above). Q cycles the
tier while a demo runs.

#### Shape × material composition

`shape` explicitly chooses `comet`, `beam`, `ring`, `pillar`, `vortex` or `circle`.
When omitted (or empty), the element picks its normal form, its stationary form for
`path: stay`, or a pillar for `start: below`. `element` supplies the primary material;
`mix: ["sand", "thunder"]` braids additional materials through the same shape. Existing
signature forms are retained where compatible; ice remains straight even if the path
says arc or spiral. A mixed spell's primary material decides this movement rule.

`start` and `end` also accept one `[x,y]` coordinate or a nonempty list of coordinates
and/or their usual anchor names. Body i cycles through that list. For example,
`start: [[500,180],[700,120]]`, `end: [[700,120],[850,450]]` composes an ordinary chain
without a chain-specific renderer. Coordinate endpoints remain fixed; named anchors
follow their actors. Coordinates refer to the stage before camera zoom.

| Field | Meaning | Default |
|---|---|---|
| `linger` | Seconds a projectile stays at its endpoint after landing | 0 |
| `fuse` | Seconds a lingering body takes to go off once another cast's burst sets it off; a row of bodies from two interleaved casts then goes off one after another | 0 |
| `burst` | Burst at its end, including every mixed material; nearby lingering bodies of other casts detonate early | false |
| `swell` | Shared shapes / wind tornado: end size multiplier; below 1 contracts, above 1 expands | 1 |

Scenery and coordinate bursts can be composed without `hit` events. Target damage / hit
counter bookkeeping still requires a paired `hit`; `burst` alone does not count a hit.
Stationary whole-volley shapes burst once at their final landing. See
[`combos/element_master/`](../combos/element_master) for the complete showcase.

### `camera` — ease the view

`{"t": 1, "do": "camera", "zoom": 1.6, "at": [460,410], "time": 0.8}`
zooms closer over 0.8 action seconds, including slow motion and hit-stop. `zoom: 1`
returns to the full stage. The camera keeps its view inside 1280×720; values below
1 are clamped to 1. Defaults: `zoom: 1`, `at: [640,360]`, `time: 0.5`.
Help and captions remain on screen. Reset / replay restores the original view.

### `move` — the attacker glides
| Field | Meaning | Default |
|---|---|---|
| `by` | `[dx, dy]` offset in px (negative dy = up) | [0, 0] |
| `time` | seconds of the glide (eased) | 0.08 |

Moves add up; keep the attacker roughly between x 380 and the target, and bring it back down
to y ≈ 450 by the end if it jumped.

### `hit` — the target is struck
| Field | Meaning | Default |
|---|---|---|
| `push` | added to the target's horizontal speed, px/s. On the ground friction (1600 px/s²) stops it, so a lone push of v slides about v²/3200 px (140 → 6 px, 260 → 21 px, 400 → 50 px); in the air it keeps drifting until it lands | 60 |
| `launch` | **replaces** the target's vertical speed, px/s: negative throws it up, a large positive one (> 500) slams it down so it bounces once | none |
| `stop` | hit-stop seconds: everything freezes, the target shudders | 0.05 |
| `shake` | screen-shake strength, px | 2.5 |
| `spark` | size of the star spark, px | 46 |
| `palette` | spark colours | normal |
| `finisher` | `true`: spark at the target's centre, 12 rays, a ring and a ground ring, longer shake, the hit counter turns gold | false |

Gravity is 1500 px/s². A launch of −v keeps the target in the air for about 2v/1500 s
(−640 → ~0.85 s, peak ~135 px up). To keep juggling, give later air hits a small negative
`launch` (−200…−300): because launch replaces the vertical speed, each one re-lifts the
target. Plan the slam to arrive before the target lands. The target can't leave the screen
(it is held between x 80 and 1200).

Every `hit` adds one to the counter and is what the self-test counts. Put it ~0.03–0.05 s
after its slash so it lands while the crescent is fully grown.

### `charge` — a gold glint gathers on the attacker
No fields. Lasts ~0.25 s; leave that much before the next event.

### `flash_step` — the attacker vanishes and reappears past the target
| Field | Meaning | Default |
|---|---|---|
| `past` | how far beyond the target it reappears, px | 140 |

Leaves a long gold streak, then the whole scene holds still for 0.1 s.

### `cut` — a straight cut drawn across the target's body
| Field | Meaning | Default |
|---|---|---|
| `angle` | direction of the cut, degrees (0 horizontal, ±35 diagonals, 90 vertical) | 0 |
| `palette` | colours | normal |

A `cut` does not count as a hit; pair it with a `hit` at the same `t` if it should.

## Run flags (for scripts)

After `--`: `--verify` (headless; prints `PASS: N hits landed`), `--capture=FILE
--capture-at=S`, `--frames=DIR --duration=S`. `tools/verify_combo.py` uses them for you.


## Ground impacts, natural groups and graph editing

See [public event fields](public_effects.md) and [multi-move graphs](multi_skill_flow.md).
