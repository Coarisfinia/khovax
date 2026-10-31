---
name: model
description: Import, rig, animate, texture and verify a 3D model (monster, NPC, prop) for khovax with Blender and Godot, from the owner's source. Use whenever a task adds or changes a .glb model, its rig, its clips or its textures, or the model tooling.
---

# Modeling playbook (owner's way)

**New models come only from the owner** (owner's base rule, #1568): agents never make a new model
from scratch. The owner gives its source (the mesh, and the rig if it has one), or for a prop or
scenery it comes from a free licensed source; agents import, rig, animate, check and fix it, and
work on the tooling. Needing a new model goes as AGENTS.md
says (#1575): a `question` issue with base prompts for a monster, a free licensed source for
anything else, and never a new model for what a retexture of an existing one resolves (#1847).

**Every base prompt for a monster ends with the same sentence** (the owner's pick on #1682):
`Two small, plain, flat black oval eyes.` Word for word, in every prompt, whatever else the
prompt says about its face. It only marks where the eyes go and how big they are: the import
replaces them with our own eyes, which blink and shut (`lib/marked_eyes.py`, below). A monster
designed without eyes leaves the sentence out and says so in its issue.

**Every evolution prompt is this copypasta** (owner, #1754; reworded by the owner's ground rule
of 2026-10-30, #1821): a baby form or any other evolution of an existing beast is asked for with
the best picture of the earlier form attached as the reference and this block, word for word, only
its two `<…>` parts differing between the issue's 20 variations. It ends with the eye sentence too.
**An evolved form redesigns its body; it never copies the earlier form's body** (owner's ground
rule, 2026-10-30, #1821): copying it isn't interesting. So each variation has a change, written as
a plain sentence, that adds something unique, unusual or fantastical, such as nine tails, a
skateboard, wings, extra heads or a landscape on its back, and its own body line saying how the
body becomes different. A form later than the pictured one looks more powerful and more
fantastical, never the same animal recoloured (owner, #1772); its body line is free per variation,
with "more sturdy" as the default. **A baby form** (owner's pick on #1823, 2026-10-30) says
`Draw its baby form.` instead of `Draw its evolved form.`, and its body line is always
`Its body also changes. It becomes younger and smaller - redesign it.`

```text
Generate a brand-new image of a creature. Draw its evolved form.
<the change, as a plain sentence, e.g. "It has grown a pair of great wings of frosted ice, folded at its sides.">

Its body also evolves. It becomes <how, e.g. "more sturdy"> - redesign it.

One single creature, centred and alone, in a front three-quarter view, its whole body in frame with space all around it. The background is plain, flat light grey and continues unbroken beneath it.
Pose: a calm, symmetrical rest pose, head level, mouth closed. No loose or floating parts, no effects such as sparks, steam or smoke.
Style: a stylized game creature with large, readable shapes and flat matte colours, smooth like a clay 3D render and ready for cel shading: plain flat colour areas without drawn outlines, painted highlights or painted shadows. Soft, even, shadowless light. No text.
Two small, plain, flat black oval eyes.
```

**Every prop prompt ends with this fixed block** (owner, #1824, #1825): a non-monster asset (the
world-asset list's props, scenery) is asked for with the first line, its own description, then the
block word for word. **No single-hex asset has a door, doorway or entrance** (AGENTS.md, #1825):
never describe one. **Runes go on only as our own engravings** (owner, #1856, #1908), added to the model later and
never drawn by the image generator, so the block says "no runes, no writing", and **the ground is ours** (owner, #1908): the ground texture comes
from the game, so the block forbids a base plate, ground or grass. **A wall or other edge piece
never asks for clean-cut or flat ends** (owner, #1908): "both ends are cut clean and flat so
sections line up end to end" makes the image generator draw tiles at the edges; the importer lines
the pieces up instead.

```text
Generate a brand-new image of a game prop for a stylized fantasy world.
<the asset, as one or two plain sentences>

One single object, centred and alone, in a front three-quarter view from slightly above, the whole object in frame with space all around it. The background is plain, flat light grey and continues unbroken beneath it; no base plate, no ground or grass under it: the ground is ours.
Style: a stylized game asset with large, readable shapes and flat matte colours, smooth like a clay 3D render and ready for cel shading: plain flat colour areas without drawn outlines, painted highlights or painted shadows. Soft, even, shadowless light. No text, no runes, no writing, no people, no creatures, no effects such as sparks, steam or smoke.
```

Every model is **built by a committed Blender script**, so it can be rebuilt, reviewed and changed
by editing code, never by hand-editing a .blend. Blender MCP (an interactive viewport) is allowed
for look-dev with the owner, but whatever it finds goes back into the script.

## Tools
- **Blender 5.2.2**, portable at `~/.local/opt/blender-5.2.2` (`blender` on the PATH). Brew can't
  install it on Linux. CI pins the same version in `.github/actions/setup-blender/action.yml`
  (#1161): a bump changes both, and every scripted model's rebuild with them. Run it headless, through `packages/game-models/blender.py`:
  `uv run --locked packages/game-models/blender.py --background --factory-startup
  --python <script.py> -- <args>`
  The wrapper puts Blender on the GPU under WSL (`GALLIUM_DRIVER=d3d12`, #1050), for that process
  only: Mesa's default falls back to the CPU's software rasteriser. It also makes a script that
  raises exit 1 (`--python-exit-code 1`, #1077): plain Blender prints the traceback and exits 0,
  so a failed check would look like a success. So every model script runs through it, also where
  `blender` on the PATH already picks the GPU (as on the owner's laptop).
  Never set it for the shell:
  Godot would pick it up, and on d3d12 its renderer breaks every skinned mesh. The MESA/ZINK/EGL
  warnings are harmless. **Render with Cycles, never EEVEE** (#1676): Blender 5.2.2's EEVEE hangs at
  render start under WSL (d3d12 and llvmpipe alike) and never ends, while Cycles on the CPU at a few
  samples renders a sheet in seconds; `render_views.py` does so.
- **Godot 4.7.2**, the CI's version: every Godot check runs in the game project itself, never in
  a scratch project, so the repo's import settings apply. It renders on the CPU (the software
  rasteriser), so `render_in_game.gd` turns off vsync and the frame cap itself: no waiting for
  the screen between frames. Blender (GPU) and Godot (CPU) renders don't compete and
  run side by side; several Godot renders at once only share the CPU's cores.
- **ffmpeg** for GIFs through
  `uv run --locked packages/game-models/gif.py <frame_dir> <Clip>` (a palette pass, looping; options in its
  header), never a hand-typed command.
- The scripts beside this file: `scripts/render_views.py` (every side, one labelled sheet, drawn
  in Blender with its own font: no ImageMagick, no system font),
  `scripts/compare_sheet.py` (the model against its reference, as a sheet and numbers, #1072). The
  Godot import check, `packages/game/tools/models/check_glb.gd`, lives in the game, where Godot can
  run it (#1101).

## Shared library and tools (owner's rule, #995)
**Tools are built reusable; a model script holds only that model's parameters and parts.** Anything
a second model could use goes into the library or a generic tool, never into one model's script.

- **The Blender library, `packages/game-models/lib/`** (a model script imports it after
  `sys.path.insert(0, <packages/game-models>)`):
  - `scene`: a clean scene at the clip rate, `apply_scale`, `triangles`, and `export_glb` (the
    export settings the game takes: GLB, skins, one animation per NLA track, Y up, every mesh's
    faces in a fixed order so a rebuild gives the same bytes).
  - `materials`: cel-friendly flat colours and emissive glows (`palette`).
  - `prop_paint` (#1853): the props' shared CC0 texture set and its triplanar mapping, moss and
    shade (below, "Props from a bare shape").
  - `body`: soft organic bodies from metaballs (`Blob`: `ball`, `ellipsoid`, `capsule`, `limb`,
    and `tube`, one smooth tapering form along a curve, such as a tail, where a `limb`'s joints
    would bulge into beads, #1171), converted and reduced to a triangle budget.
  - `parts`: rigid pieces weighted to one bone (`part`), faceted `crystal`s (with an optional
    `curl`), curling fur `tuft`s.
  - `surface`: patterns laid on a body and bending with it: glowing `vein`s, whose loose ends
    taper out to a point (`taper`, #1171), and `rune`s (`GLYPHS`).
  - `eyes`: a detailed `eye` (eyeball, glowing iris, slit pupil, glowing rim, brow; no glint, the owner on #1716), where
    it looks out from (`spot`) and which way (`look`); a smaller brow with `brow_size`, whose top
    edge stays over the eye (#1249); with `lid`, a lid on a bone of its own (#1304), which
    `Lids` adds to the rig and, as an `animate` overlay, shuts in Sleep, at Faint's end and in a
    blink now and then in Idle (its bones go into `weights.bind`'s `rigid_bones`); `mirrored`
    makes a right eye from a left one, lid included. Nothing of an eye pokes through its lid at
    any point of its swing (#1690): `clipped` measures it against the lid's mesh, `eye` grows a
    narrow eye's lid taller until nothing does, and `Lids` fails the build if anything still does.
  - `marked_eyes` (#1683): our eyes in place of a generated model's. `replace` finds the two
    flat black ovals the prompt's eye sentence marked on the head (`GLOW` instead of `DARK` for a
    beast imported with glowing painted eyes), paints them over in the skin's colour around them,
    fits `eyes.eye` with lids there by their position, size and spacing (`clear` sets them out
    along the way they look where the head's skin covers least of their iris and pupil, and
    fails the build past `BURIED`), joins them into the skin, and returns the `Lids` (for `animate`'s overlays) and the eye points (for
    `attachments.add`). It prints an `EYES` line with what it found. Eyes the generator modelled
    as pieces of their own (glowing balls, #1733) are `find`-ed, taken out with `modelled` (each
    mark growing to its ball's size) and handed to `replace` as `marks`.
  - `frostfire` (#1733): the frost-and-fire line's paint on `repaint`, magma on the right side
    and ice on the left with cracks across both, plain soles; the Frostfire Hound and its pup,
    the Kavrikka, share it, each with its own `Look` (size, midline, seed).
  - `muzzle` (#1026): a canine `Snout`: the brow, stop, bridge and lips melted into the head's
    `Blob` (`upper`), and its own pieces (`parts`): a soft lower jaw on the jaw bone, sized as
    shares of the upper muzzle above it, the mouth's dark lining that shows when it opens, the
    nose pad and the fangs; length, taper, stop depth, lips, jaw depth and width and the chin's
    reach as parameters.
  - `quadruped`: `Proportions` and `armature` (spine, neck, head, jaw, ears, tail, four
    four-bone legs, `.L`/`.R`), and the trunk's weights: `bind_underside` keeps the skin between
    the legs (the chest's and throat's underside, the belly, the back between the shoulder blades)
    with the spine and neck rather than the legs, so the body keeps its volume as a leg swings or
    folds (#1422, the volume check), and with `brisket` gives the brisket between the forelegs
    to the chest rather than the neck, so a bowing neck doesn't crease it (#1437); `bind_torso` does the same by height for a low trunk.
  - `weights`: `bind` (automatic weights, pieces joined in, at most four bones, normalised), and
    `root`, which moves a stiff piece (a crystal, a tuft) whole as the skin at its root, so it
    stays on the skin where two bones share it (#1303), following only the bones it names (a
    crest the trunk's: the shoulder blades' share stays with the spine, so a walk doesn't rock it).
  - `clips`: `Clip` (a clip's keys, whether it loops, its paws' steps and whether its paws are
    planted), `cycle_frames` (gait timing from the game's speed), `gait` (every frame posed:
    paws planted for `duty` of the cycle and running back at the game's speed, lifting and
    landing on smooth paths, the body bobbing and rolling over the planted legs, the head
    countering the bob; `planted=False` swings the legs freely, for a run too fast for planted
    legs at the clip rate) with the phases `WALK` (four beats), `TROT` and `GALLOP`, the
    quadruped set (`idle` breathing, shifting its weight over planted paws and twitching one ear
    at a time, as waves that run a whole number of times a loop, #1196; the one-shots posed as anticipation, action, overshoot and settle,
    #1074: `attack` with its forepaws stepping out, `hit` with a shiver and an ear flick, `faint`
    with its legs folding under it and a moving hold; `channel`: a long attack held for as long as it lasts, as a wind-up
    `ChannelStart`, the looping `Channel` and a release `ChannelEnd` the game plays in turn,
    #1158; `feed`: the head lowered to the ground, lapping or tearing in a loop, its reach to the
    ground set per body plan, #1281), `FOLLOW` (the quadruped's chains and their springs), `LEGS` (its legs for
    `legs.plant`) and `animate` (fills, follows, plants the paws, keys every bone on every frame,
    cycles the loops' curves, stashes every clip, and with `ground_meshes` lifts the root, eased,
    wherever a pose sinks into the ground, the legs reaching down to their paws again).
  - `legs` (#1073): planted paws. A paw stays where it stands unless a clip's `plant.<paw>`
    channel or a `Step` moves it, and every leg reaches for it by analytic IK on every frame
    (`Leg`: two bones bending between them and a follower: a hind leg's hock turning with its
    thigh, a foreleg's forearm swinging with the leg), keyed as plain rotations: no constraint or
    bake reaches the export. Where a planted leg can't reach, the body comes down onto it; past a
    share of its reach a leg eases toward straight (soft IK) rather than snapping.
  - `motion` (#1071): `fill` (sparse keys to every frame, smooth and clamped, across the seam
    on a loop; a key may name the ease of the move into it, per channel too, from `EASES`:
    `quart` and `expo` snap, `back` overshoots, `elastic` wobbles, #1074), `Shiver` (a
    one-shot clip's tremble, growing and dying away) and `follow` (overlap and follow-through: each chained bone trails its parent
    through a small second-order spring, so parts don't all start and stop at once).
  - `ground`: ground contact (`lowest`, `settle`, `report`).
  - `wisps` (#1103): pieces hovering around a body on their own, each on a bone hung from the
    root and held in the model (a `loc.<bone>` channel, which `animate`'s keys turn into the
    bone's shift whatever the root does): `Wisps.drift`, an `animate` overlay, hovers them slowly
    in every clip, the wave flowing along the body, and a `Gather` sends them to a ring during
    one clip (the attack) and back, or holds them on it across clips played in turn (the long
    attack); with a `bone`, the ring trails that bone (the head) through a soft spring (#1164), and with a
    `rise` the wisps fly over the body to it and back, not through it (#1182).
  - `pulse` (#1224): a part that swells and settles on beats (a crystal flaring in step with the
    wisps' ring, `wisps.Gather.frames_at`), on a bone of its own whose scale an `animate` overlay
    keys in every clip (a `scale.<bone>` channel); `metrics` counts its bone as its parent's.
  - `starfield` (#1635): our own starry sky as an equirectangular texture from a fixed seed,
    every star one of two fixed shapes (a soft dot, or a four-pointed sparkle for the brightest),
    a steep brightness falloff, faint tints and a deep gradient with a haze band; `uv` maps a
    surface around its middle onto it, and `disc` paints a spot (an eye). Never a generated
    (AI) sky: its stars each have a different number of points.
  - `repaint` (#1609): a generated model's texture painted anew from where each texel lies on
    the body, for a download whose paint is a patchwork of islands: `Texels` gives every covered
    texel its spot, face normal and face at rest, `pieces` the mesh's connected pieces (a tail, an
    eye), `Cells` cellular noise from a fixed seed (cracked rock or ice running across the
    islands' seams), and `image` the canvas as a packed image, its gaps filled from the islands'
    edges (`dilate`).
  - `imported`: a built `.glb` read back as the game imports it (its clip rate and loops from
    the `.import`), for the checks and plots.
  - `symmetry`: `check` fails the build when a left part (`.L`) isn't its right twin (`.R`)
    mirrored across X; a model script runs it on its parts before they're joined.
  - `parts.claws`: claws fanned out along a paw's front like toes, the middle ones longer, curving
    down; count, spread, size, fan and curl as parameters.
  - `metrics`: proportions as numbers (#1072). A model script keeps a `REFERENCE` dict of its
    approved ratios (head/body, leg/body, ear/head, tail/body, eye spacing/head width, the
    eyes' symmetry, the snout's: the muzzle against the head, the lower jaw against the muzzle, ...) and its build ends with `metrics.report(rig, [skin], REFERENCE)`, which
    prints each as a measurement against the reference and fails the build beyond the
    tolerance. A new model measures itself first (a measure missing from `REFERENCE` prints as a
    note), and its `REFERENCE` takes the values once the owner approves the look.
  - `attachments`: `add` gives the rig its attachment points (below), each a small bone that
    deforms nothing, parented to the bone it moves with; `eyes.spot` is where an eye looks out,
    and its bone points the way it looks (`eyes.look`), so the game's eye glow shrinks into an
    eye turned away from the camera (#1171).
- **The ground check:** `packages/game-models/check_ground.py -- <model.glb> [tolerance]` samples every
  frame of every clip and prints, per clip, the lowest point of the deformed mesh and of each
  paw or foot; it fails when anything sinks below the ground (z = 0) by more than the tolerance.
- **The motion check (#1071):** `packages/game-models/check_motion.py -- <model.glb> [<Clip>=<speed> ...]`
  samples every frame of every clip and prints, per clip, **foot sliding** (a paw's speed over
  the ground while it stands on it, against the speed the game moves the model at while it
  plays that clip; the model script prints them; every clip, one-shots too), the **loop seam** (pose, every bone's shift, the
  wisps' `loc.` channels too, and roughness from the last frame to the first), the **joins** of a loop to its lead-in and lead-out (`<Loop>Start`,
  `<Loop>End`) and **jitter** (how rough the roughest joint curve runs); it fails
  past its limits (in its header).
- **The clearance check (#1227):** `packages/game-models/check_clearance.py -- <model.glb> [tolerance]`
  samples every frame of every clip and prints, per clip, the smallest gap between a wisp and the
  rest of the mesh, the frame, and the wisp and body bone it's between; it fails when a wisp's
  faces cross the body's, a wisp sits inside it, or the gap falls below the tolerance
  (`lib/clearance.py`).
- **The brow check (#1249):** `packages/game-models/check_brows.py -- <model.glb> [tolerance]`
  looks at each eye (its `eye.*` point and the pieces `eyes.eye` built around it) every other frame
  of every clip, from the model's front, from the eye's side and straight into it, and fails when
  more of the eye than the tolerance shows above a brow (or anything lying on the eye) crossing it:
  a brow may overlap the eye, but the eye's top never shines through above it (`lib/brows.py`).
- **The covered-eye check (#1758):** `packages/game-models/check_eyes_covered.py -- <model.glb> [tolerance]`
  looks at each of our eyes straight on, along the way it looks, at rest and every other frame of
  every clip, and fails when the body (anything but the eye's own eyeball, iris, pupil, rim, brow
  and lid; a generated skin's loose pieces included) covers more of the eye's face, within its
  rim, than the tolerance (`lib/covered.py`).
- **The volume check (#1306):** `packages/game-models/check_volume.py -- <model.glb> [share]`
  samples every frame of every clip and prints, per clip, the smallest share of its rest depth or
  width the body keeps at a station on the spine or neck, the frame, the station and which; it
  fails below the share (`lib/volume.py`). Its `KNOWN` list and `check_clearance.py`'s are judged
  alike (`lib/known.py`).
- **The connectivity check (#1403):** `packages/game-models/check_connectivity.py -- <model.glb> [tolerance]`
  cuts the mesh into pieces (welded by position), gives each part (a crystal, a claw, a tuft) the
  nearest larger piece at rest as the skin it sits on, samples every frame of every clip and prints,
  per clip, the most a part's gap to it grows beyond its gap at rest, the frame, the part and that
  piece, and likewise the most a part sinks into it (the share of its vertices inside beyond the
  share at rest, #1458); it fails past the tolerance or `SINK` (`lib/connectivity.py`). Wisps are
  exempt. Its `KNOWN` list is judged like the volume check's. `test_connectivity.py` tests it on a
  box with a part that stays, dips, lifts off and sinks in.
- **The footprint check (#1520):** `packages/game-models/check_footprint.py -- <model.glb>`
  measures the rest pose and every frame of every clip and prints how far the model's meshes reach
  across the hex the game stands it on, seen from above (1.00 at the hex's edge), and the frame. It
  fails a regular monster past 0.95 at rest (5 % padding inside), 1.30 in its Attack and 1.05 in
  its other clips, and one in its `LARGE` set (a boss, an enraged or stronger monster) past 1.05 at
  rest, 1.30 in its Attack and 1.10 in its other clips (`lib/footprint.py`). A prop (a model
  without a rig or without a Walk clip, such as a gate or an egg) is held to limits of its own:
  0.95 at rest and 1.00 in every clip, a static one by its rest pose. Nothing is let off through
  an exemption list (#1641): a model too big for its hex is shrunk in its script. A tile's
  decoration (a model a tile blueprint names) is the tile's own look, not a thing on it, and isn't
  measured (the owner, on #1651). A pack's model (no script here: the figure, the chest) is
  measured as each view that puts it on the board shows it (#1652, `lib/views.py`): at the view's
  `MODEL_SCALE`, without its `HIDDEN_PARTS`, standing in its `IDLE` clip and in its `CLIPS`,
  against a prop's limits; so a view that shows a pack's model names these constants. An item's
  model no view preloads (shown only in the gear panel) isn't measured. Its `KNOWN` list
  is judged like the volume check's. `test_footprint.py` tests it on boxes that fit their hex or
  are too big for it.
- **The world-scale check (#1837):** `packages/game-models/check_world_scale.py -- <model.glb>`
  measures each model against the world's scale (`lib/world_scale.py`): a model that isn't a
  monster by the kind its script names, the players' figure against the player's height (step
  23). `test_world_scale.py` tests it on boxes of each kind, sized to it or off it.
- **The dimensions check (#1299):** `packages/game-models/check_dimensions.py -- <model.glb> [...]`
  measures each limb at rest per body plan (forearm against upper arm, shin against thigh, the
  foreleg against the shoulder's height) and fails a measure outside its range
  (`lib/dimensions.py`, where the ranges and their reasons are).
- **Short check output (#1524):** the motion, ground and clearance checks take `--summary`: one
  line per clip and limit it misses, with the value, the limit and by how much, and the passing
  clips on one line (`lib/summary.py`). Read those while tuning, not the full logs.
- **The gait sweep (#1524):** `uv run --locked --package khovax-game-models
  packages/game-models/sweep_gait.py packages/game-models/<name>.py
  packages/game/assets/<name>/<name>.glb NAME=a,b,c ... [--clips Walk,Run] [--keep <folder>]`
  builds the model over the grid of gait values in parallel, runs those three checks on each in
  summary mode, and prints a Markdown table: `PASS`, or the limit each combination misses most
  and by how much. A model script offers its gait values as module constants named in its `GAIT`
  and takes `NAME=value` after its output path (`lib/tuning.py`, as `drakkudor.py` and the
  quadrupeds do). Set what follows from them (a quadruped's cycle frames and strides from its
  `*_TILES`) after `tuning.arguments` has run, so a swept value reaches it. Tune a gait with a
  sweep or two rather than hand-run rounds of build and check, then write the chosen values into
  the script.
- **The curve plots (#1071):** `packages/game-models/plot_motion.py -- <out.png> <Clip> <model.glb>
  [<before.glb>]` draws each bone's turn over a clip, a loop twice through with its seam
  marked, the previous build faint behind: stiffness, overlap and a stop at the seam read better
  from a curve than from a GIF.
- **The renders:** `scripts/render_views.py` (every side in Blender) and
  `packages/game/tools/models/render_in_game.gd` (any `.glb` in the real game scene: six sides,
  the game camera, the codex close-ups `portrait` and `face`, or a clip's frames; usage in its header).
- **A new model** starts from its source (above), never from scratch (#1568): turn it into the
  source the script builds from with `packages/game-models/import_source.py` (usage in its
  header; it adopts a rig the source already has), then place, rig and animate it like the
  existing scripts (`attachments.add`, `weights.bind`, `clips.animate`, `scene.export_glb`). The
  scripted models built from the library (`mana_wolf.py` and others) stay maintained; a body plan
  the library lacks (a bird, a serpent) becomes a new library module first.

- **Running the tools** (owner's rule, #995): long-running work (Blender builds, renders, Godot
  render scripts, GIF assembly) runs in the background (`run_in_background`) and is monitored,
  never in the agent's foreground: keep working and answering messages, check the output files,
  and react when it finishes. Independent renders run in parallel (owner, #1047).

## Generated models (Meshy): the order and the traps (#1526)
A model whose mesh and colour come from the owner's Meshy download (as Drakkudor's do,
`packages/game-models/drakkudor.py`) goes through these steps, in this order:

1. **Generating in Meshy** (the owner generates; owner, #1671): **triangle** topology at about
   **6,000 triangles**. That budget comes out a bit flawed now and then (thin parts merged into
   lumps, holes, stray faces); fix those spots by hand on import, never by asking for more
   triangles. **The owner's raw export goes to the private repository
   `Coarisfinia/khovax-sources`** (#1849): one folder per issue (`<issue>-<slug>/`), each file
   named after its asset (`<slug>.glb`, a variant with a suffix); the import issue links the file,
   and the import takes it from there as the `<download.glb>` of steps 2 and 3. The face carries only the prompt's two flat black ovals
   (#1682), never eyes Meshy draws or details: ours replace them (step 5). Meshy rigs it first wherever it can (#1514);
   where it can't, we build our own Blender rig (#1732, section 2). An evolution's image comes
   from the copypasta above (#1754).
2. **Inspect:** `uv run --locked packages/game-models/inspect_meshy.py <download.glb>` (#1523),
   one report on its mesh, material, painted eyes, body columns and rig. Read it before measuring
   anything by hand. It warns when the download is far above step 1's triangle target.
3. **Import and strip:** `packages/game-models/import_source.py` makes the source the script
   builds from (`packages/game-models/sources/<name>.glb`): only the base colour, opaque,
   single-sided and matte (#1476). A download Meshy has rigged keeps its skin and rig, adopted
   by `lib/rigged.py` (#1516): its chains checked against the parts they move, a short one
   regrown and one bleeding into another's part cleaned, its bones named to the library's scheme,
   and the model placed on its feet under a `root`. Read what it prints (`KEEP`, `FIX`,
   `RENAME`).
4. **Scale to the hex, first:** settle the model's size before any clip, gait or render
   (#1522). The gait's limits depend on the size, and Drakkudor's late rescale redid its gait and
   every render. `import_source.py` fits a rigged download to its hex by itself: its `scale` is
   `hex` (the default) for a regular monster and `hex-large` for a boss, enraged or stronger one,
   sizing the rest pose within the footprint check's limits (step 20 below) with a margin for the
   widest clip (`lib/footprint.py`'s `fit`). Read its `HEX` line, and confirm the fit with the
   check once the clips exist; a `hex-large` model goes into `LARGE` in `check_footprint.py`
   first, or the check holds it to a regular monster's limits. An unrigged download is sized by its model script (`SCALE`, as
   `drakkudor.py` does), to the same limits.
5. **Rig:** start from the rig the import adopted (the owner rigs in Meshy first, #1514), and
   check its fixes bend right (bend each chain and see that it moves only its own part). An
   unrigged download is rigged by the model script, as `drakkudor.py` does with `lib/hexapod.py`.
   Once the head bone is named, swap in our eyes: `marked_eyes.replace(rig, skin, mats, faint)`
   before `attachments.add` (its eye points) and `clips.animate` (its `Lids.shut` among the
   overlays), and read its `EYES` line.
6. **Clips:** the full creature set through `clips.animate`, as for any model; tune the gait
   with the gait sweep, not by hand.
7. **Checks, renders, PR:** the checks of section 4, `render_media.py` for the pictures, then
   section 5.

**The traps found on Drakkudor (#1476, #1514):**
- **Seam splits:** the export splits a vertex wherever its UVs part, which broke the volume
  check's body detection; `lib/volume.py` handles it now. A new check reading the mesh welds by
  position too.
- **Painted eyes:** the generator paints its eyes on the texture; they can't blink or shut. The
  prompt marks them as flat black ovals (its fixed eye sentence, above), and the model script
  swaps in ours with `marked_eyes.replace` once the bones are named (#1682): the eye check fails
  a creature without them.
- **Custom normals:** Blender's glTF import keeps a file's normals as custom ones, the model
  script's import of its source too, and `scene.sort_mesh` (in `scene.export_glb`) refuses them:
  right after importing the source, clear them
  (`bpy.ops.mesh.customdata_custom_splitnormals_clear()`) and shade smooth, as `drakkudor.py`
  does.
- **Material:** single-sided (backface culling on), opaque (no alpha link, alpha 1) and matte
  (no metal or roughness map, roughness 1); `import_source.py` does it, and `inspect_meshy.py`
  shows what the download had (its `doubleSided` and alpha mode).
- **A new body plan** (such as six legs) needs its plan in `lib/dimensions.py` first (its ranges
  and their reasons, as `hexapod` has), or the dimensions check has nothing to measure.
- **Meshy's auto-rig** is scaled to a person's height (1.7 tall) and has no clips. Its chains can
  stop short of their part or bleed into a neighbour's (#1519); `lib/rigged.py` fixes both, but
  check its `FIX` lines. Its legs have more bones than the library's three-bone `legs.Leg` plants
  (#1539).
- **Weights:** automatic weights fail on thin parts over a hollow (ribs over a ribcage): they
  can't tell a leg from the rib beside it. Weight by where each vertex lies instead, as
  `hexapod.bind` does.

**The traps found on the starry egg (#1635)**, a static prop the generator rigged anyway:
- **A rig on a prop:** `import_source.py`'s `static` drops it, and the model script exports the
  mesh without a rig or clips (as `mana_gems.py`). `check_glb.gd` and `check_ground.py` expect a
  rigged creature and don't apply.
- **Shading in patches:** clearing the custom normals leaves the seam splits apart, so a smooth
  surface shades island by island. Weld by position (`bmesh.ops.remove_doubles`, UVs stay on the
  corners) and shade smooth by angle, keeping a crack's rim sharp.

**The traps found on Fohossa (#1619)**, a four-legged Meshy auto-rig with a long trunk:
- **One piece for every leg:** with a long spine between the hips' fork and the withers' fork,
  the belly joins all four legs into one piece outside the forks' balls, and `rigged.adopt` took
  it for one leg's part (it stripped the other legs' weights as bleeds). `rigged.split` now parts a
  piece that several chains call home by their weights (`SPLIT` line).
- **An empty toe bone:** the auto-rig ends each leg with a bone below the sole that weighs almost
  nothing; the hoof is on the bone before it. It is folded (`FOLDED ... moved almost none`), so the
  hoof's bone is the paw the clips plant and the ground checks leave to the legs.
- **Names the clips key:** `rigged` names only legs and stalks; the model script renames the rest
  to the quadruped's scheme (`spine_NN`, `neck`, `head`, `tail_NN`, the legs' `scapula`,
  `upper_arm`, `forearm`, `thigh`, `shin`, `hock`), so the clips, the volume check's stations and
  the dimensions check find them. A trunk bone pointing back to the tail (the pelvis) must not be
  `spine_01`: the volume check's station between two bones pointing apart has no plane. A bone
  weighing almost nothing (a short one under the skull) goes into its neighbour.
- **Shoulders and belly:** the forelegs hang from the withers, not the neck, and the legs' tops
  give up their weights near the midline to the trunk (`keep_trunk`), or a swinging leg drags the
  chest's underside and a bowing neck pinches between the shoulders (the volume check).
- **Reach:** its legs are short against its body, so the wolf's clips' body shifts, paw steps and
  tail swings are scaled down (`lesser`); the footprint and the legs' reach show by how much.

**The trap found on Nuvvoluvvo (#1620, #1725)**: both ears' chains hang from the head, whose skin
is one piece with the ears, and `rigged.adopt` gave that piece to one ear and regrew its chain
toward the muzzle, while the other ear stayed `UNMATCHED`. It now fixes mirror twins (a `.L` and a
`.R` chain off one chain) alike (`TWINS` lines): a piece only one twin finds is neither's, a
twin's loose end is folded only if its twin's is too, and a short twin is regrown only toward
where its twin goes (its twin mirrored), and not while its twin is short too but can't be. A
short chain whose part the body holds isn't regrown (`WEIGHTLESS`): rig it by hand, as
`nuvvoluvvo.py` mirrors its right ear's rig.

**The traps found on the Frostfire Hound (#1609)**, a four-legged Meshy auto-rig with few bones:
- **A white glow:** a download with an emissive map kept its white emissive factor once the map
  was dropped, and glowed all over; `import_source.py` now turns the glow off.
- **No parts at all:** where a fork's ball reaches past most of the legs (a long first leg bone
  from the shoulder to the elbow), `rigged.adopt` finds no part outside the balls, prints
  `UNMATCHED` for every chain and names them `chainN_NN`. Read each chain's bones and weights
  (`inspect_meshy.py` on the source) and name them in the model script, as `frostfire_hound.py`
  does.
- **A stub of a thigh:** the auto-rig put the hind knee high under the hip (the dimensions check:
  shin/thigh 1.58). Move the joint to where the mesh bends and give the skin above it to the
  thigh.
- **A messy paint:** repaint it by position with `lib/repaint.py` rather than editing the atlas.

**The traps found on the Kavrikka (#1733)**, the hound's pup, a Meshy auto-rig of a puppy:
- **Modelled eyes:** its eyes were glowing balls of their own, which no repaint hides, and its
  magma cracks glow too: find the eyes by their hues (`marked_eyes.glow`), take the balls out
  (`marked_eyes.modelled`), then paint and fit ours with the marks.
- **Toes and heels:** each paw ended in one or two toe bones (one more on one side than the
  other) and the heel's skin hung on the hock, so the heel sank into the ground as the hock
  turned and the clips couldn't settle (`still sinking`); fold the toes into the paw and give
  the heel's skin to it.
- **A trunk on the legs:** the auto-rig weighted most of the trunk to the legs' tops, so a
  swinging leg thinned the chest (the volume check): give the shoulders', haunches', belly's and
  brisket's skin to the trunk, as Fohossa's `keep_trunk` does.

## The player's clips: one Meshy export per clip, merged into a library (#1935)
Meshy rigs one clip per export (#1934): the owner exports each clip from the same rigged baseline
body into `Coarisfinia/khovax-sources` (`1827-baseline-body/`). The clips are kept **apart from the
body**, as a clip library of their own, so a later body plays the same clips:

1. **Each export becomes a clip source:** `uv run --locked packages/game-models/blender.py
   --background --factory-startup --python packages/game-models/import_clip.py -- <export.glb>
   <Clip> packages/game-models/sources/player/clips/<Clip>.glb`, named after the clip the game
   plays. It keeps the rig and its one clip, without the body (`lib/clip_sources.py`: a stand-in
   triangle carries the rig as a skin). `rest` instead of a clip name writes the rig alone, the
   library's skeleton (`sources/player/skeleton.glb`), which every clip must share.
2. **The library's build merges them:** `player_clips.py` puts every clip source onto the one rig
   and exports `packages/game/assets/player/player_clips.glb`. It **fails when a clip source's
   skeleton differs** from the skeleton's (a bone missing or extra, another parent, another rest
   pose; `lib/skeleton.py`, read from the .glb as Godot reads it), naming each difference in a
   `SKELETON` line. CI builds it with every model (step 14), so a clip from another rig fails there.
3. **Godot maps the rig to its humanoid profile:** the library's `.import` gives its skeleton a
   `BoneMap` with `SkeletonProfileHumanoid` (Meshy's Mixamo names, as Godot imports them, to the
   profile's bones), so its tracks turn `%GeneralSkeleton:<profile bone>`. Any body imported with
   such a map, Meshy's or not, plays the same clips. The boot flow checks the library loads with
   its clips on the profile's bones (`UNWORN_CLIPS`) until the body's view plays it.

A new body still needs its contacts and clearances checked against the clips, since its
proportions differ.

## Props from a bare shape: the shared texture set (#1853)
World props are generated as **shapes only** (5 credits, the owner's pick on #1846) and textured
by us; creatures and the player keep Meshy's texture (15). **There is one small texture set for
every prop**, in `packages/game-models/textures/` (stone, sandstone, wood, moss): CC0 textures
(Poly Haven, ambientCG) that `prop_textures.py` downloads by pinned checksum and reduces to a few
flat tones, so they keep their surface detail but suit the cel shading. Never a texture of a
prop's own, and never another grey stone. A prop's script only maps its parts onto the set
(`lib/prop_paint.py`), as `standing_stone.py` does:

1. Import the download with `import_source.py` (it has no texture to keep) and place and size it
   in the script (`footprint.spread`, a prop's limits), to the world's scale for its kind
   (`WORLD_SCALE`, below).
2. `prop_paint.box_uv` projects the textures triplanar (baked into the UVs, the same size on
   every prop); `prop_paint.material(<name>)` is each of the set's materials. Give each part its
   material (`repaint.pieces` tells the parts apart), the moss to the faces `prop_paint.mossy`
   picks (top and ledges), and darken crevices and the foot in flat steps with
   `prop_paint.shade` and `write_shade` (the vertex colours the texture is multiplied by). A
   coarse part is cut finer first (`bmesh.ops.subdivide_edges`, flat) for a cleaner moss edge.
3. A part the game lights (a glow) is `prop_paint.glow(<name>, <colour>)`, its emission off in
   the file.
4. The `.import` embeds the textures uncompressed (`gltf/embedded_image_handling=3`, as the
   egg's), so Godot extracts no copy beside the model. A model nothing places yet goes into the
   boot flow's `UNPLACED_MODELS`, by its id. Its `SOURCE.md` names the set's textures it uses.

**Every model is a resource of the default pack** (#1864): a new `.glb` gets an entry in the
`models` of `packages/game/slices/resource_packs/data/default.jsonc` (`"model_<name>":
"assets/<name>/<name>.glb"`), and content files and views name it by that id, never by its
`res://` path (`resource_packs_check.py` in CI).

A new material goes into the set (`prop_textures.py`'s `SET` and `textures/SOURCE.md`), for every
prop. **Any free texture under a licence AGENTS.md allows for assets is permitted** (owner, #1825;
#1511: CC0, or CC BY with credit): its source and licence go into `textures/SOURCE.md`, its licence
file beside it, so the generated `CREDITS.md` credits it where the licence asks. **When the set
falls short**, a prop is textured in Meshy after all (10 credits more): painted detail the set can't
place (a sign's lettering, a banner's pattern, a face), or the owner preferring Meshy's look for it.
No runes or carvings by script: they come from the rune set (#1855) and the engraving work (#1856).

## 1. Build (Blender script)
- **Where:** `packages/game-models/<name>.py` builds the model, and
  `packages/game/assets/<name>/<name>.glb` is its output, with `SOURCE.md`, a license and a
  `CREDITS.md` entry, as AGENTS.md's asset rules say.
- **Look:** cel-shaded eye candy, medium-poly for anything the camera sees up close (AGENTS.md,
  #69). It must read from the game's top-down camera, so the shape comes from the silhouette
  first and the detail second. It must also look good **up close**, since its codex page shows
  it full-screen (owner, #995): soft forms, and detailed eyes, snout, ears and paws.
- **Variety:** monsters may be, and are encouraged to be, obscure, barely alive, mystical or
  warped (a swirling vortex with glowing rocks for eyes); not every monster has four legs and
  barks (owner, #990). The library mustn't assume quadrupeds: `quadruped` is one body plan, and a
  body without legs (a vortex, floating rocks, a blob) must be buildable from it too, from `body`,
  `parts`, `surface`, `eyes` and its own rig module.
- **Baseline:** the mana wolf (#995) is the baseline for the level of detail: every new model
  matches or exceeds it up close (owner). Its build script, `packages/game-models/mana_wolf.py`, and its
  renders on the `assets` branch (`pr-995-v2-*`, the close-ups `pr-995-v2-portrait.png` and
  `pr-995-v2-face.png` first) are the reference.
- **Scale and placement:** the origin at the feet, facing +Z after import (glTF's forward,
  Blender's -Y; `Vector3.MODEL_FRONT`), like every model in the game: the views turn a figure with
  `atan2(heading.x, heading.z)`, so one built facing -Z walks backwards. The height matches the
  model it sits beside in the game (measure the reference .glb).
- **The world's scale (#1837):** a hex, a wall and the player are sized against each other, and
  `lib/world_scale.py` holds the numbers; read them from there, never copy them. The hex is
  `HEX_SIZE` from centre to corner (one edge is `HEX_EDGE` long, the hex `HEX_WIDTH` across its
  flats), the player `PLAYER_HEIGHT` tall (the players' figure standing, which the check
  measures), and a wall `WALL_HEIGHT`, a quarter above the player. Every model that isn't a
  monster names its kind in its script, `WORLD_SCALE = "<kind>"`, from `KINDS` there: `prop`
  (on one hex: a well, a campfire, a signpost), `portal` (on one hex, walked through), `wall`,
  `gate` and `ruined_wall` (**edge pieces**: along Blender's X, centred on the origin at the
  edge's middle, `HEX_EDGE` long, so pieces meet end to end at the hex's corners), `tower` (at a
  hex corner, above the walls) and `ruin`. Its height must be in its kind's range. Size it in its
  script, then confirm with the world-scale check (step 23). A kind a new model needs is added
  to `KINDS` with its range, in the pull request that needs it.
- **Mesh health:** apply transforms, recalculate normals outside, no loose or non-manifold geometry.
- **Reproducible (#1085):** a rebuild from an unchanged script gives the same file, byte for byte,
  so a pull request shows whether its build changed the model and two builds compare by hash.
  `scene.export_glb` puts every mesh's vertices and faces in a fixed order first, and starts each
  face's corners at its lowest vertex (Blender's UV sphere lays out its faces in a different order
  on every run, the exporter writes triangles in face order, and it splits a face into triangles
  from its first corner on; #1639, #1662).
  A step that still varies between runs is a bug to fix in the library (a fixed seed, a sorted
  order), never something to commit whichever build came out. Step 14 checks it.

## 2. Rig
**Every beast is rigged and beautifully animated by us** (owner, #1732, #1754): when the owner
says "no rig possible", only Meshy can't rig the export. We build the rig ourselves in Blender: a
custom skeleton for an odd shape (a ribbon, tentacles, a limbless body), with the full set of
clips. Ask the owner only when it's unclear what should move how.
- **Armature:** a full chain per limb (at least three bones per leg), spine, neck, head, jaw where
  it has one, tail and ear chains where it has them. Bones named left/right with `.L`/`.R`.
- **Weights:** automatic weights (`ARMATURE_AUTO`) as a start, then fix by script where they
  fail. At most four bone influences per vertex, normalised.
- **Clips:** one action per state the game plays. Every creature carries the full creature set
  (owner, #1157), named once in `packages/game-models/lib/clip_set.py`: `clips.animate` refuses a
  creature without one of them, and CI's `check_clip_set.py` fails a committed creature `.glb`
  that lacks one (every skinned model under the game's `assets/` except the non-creatures it
  lists). A clip every creature gains goes into that set, with every creature's rebuild in the
  same pull request. Read the view that will use the model too, and cover the clips it plays.
  Looping clips start and end on the same pose, and the walk speed matches how fast the game
  moves the entity (no foot sliding).
- **Fluid, not stiff (the owner's pain point, #1075, #1071):** never key every bone on the same frames so every part
  starts and stops at once. A one-shot clip is pose to pose with timing (#1074): an
  anticipation, a fast action (a snappy ease), an overshoot and a slow settle, and a hold that
  keeps moving rather than a frozen last pose. Build clips as `clips.Clip`s through `clips.animate`, which fills
  them in (`motion.fill`), lets the chains trail (`motion.follow`, with the body plan's chains,
  like `clips.FOLLOW`) and cycles the loops' curves so a loop never eases to a stop at its seam.
  A four-legged walk is four beats (`clips.WALK`), not a trot. Paws stay planted (`legs`,
  #1073): give a clip's legs no angles; move a paw with a `legs.Step` and let the legs reach.

- **Attachment points (required, owner, #1007):** every model names its eyes and its centres of
  attack, so the game can place effects there (an eye's glow, an attack's flash) and they follow
  every clip: one point per eye, `eye.L`, `eye.R` or `eye.<name>` (any number, none for a model
  without eyes), and one per thing it attacks with, `attack.0`, `attack.1`, … (at least one: a
  mouth, each striking arm). Add them with `attachments.add` before binding; the game reads them
  with `ModelPoints`, and `check_glb.gd` and the boot flow fail a model that attacks without one.

## 3. Textures and materials
- **Few materials:** at most about four per model, and one texture atlas where possible
  (≤ 1024², power of two) so it stays cheap on mobile and web.
- **Shading:** flat or ramp-friendly colours that survive the game's cel shading; a glow via an
  emissive colour, which the Compatibility renderer shows on web and Android too.
- **Export:** `bpy.ops.export_scene.gltf(filepath=..., export_format='GLB', export_animations=True,
  export_skins=True)`, then commit the `.glb` and its `.import`, with looping clips set to loop
  there (as `Rogue.glb.import` does).

## 4. Verify (every item gives an image or a number for the PR)
1. **Every side:** `uv run --locked packages/game-models/blender.py --background --factory-startup
   --python .claude/skills/model/scripts/render_views.py -- <model.glb> <out_dir> [clips] [frames]`. It
   writes front, back, left, right, top and a three-quarter view, and `sheet.png`. **Look at it.**
   Check the proportions, gaps, stretched textures and anything floating or clipping.
2. **Deformation stress:** render the extreme frames of each clip, plus a pose with each major
   bone bent ±45°. Joints must not collapse or tear. Give `render_views.py` every clip and frame at
   once (`Attack,Hit 1,8,14`, or a range `1-14`): Blender starts once, which is most of a render's
   cost, and each pose gets its own folder (`<out_dir>/Attack_008/`).
3. **Silhouette:** a flat black render from the game camera's angle. Is it readable as what it
   is, at the size it has on screen?
4. **Godot import, in the game project:** after `godot --headless --path packages/game --import`,
   run `godot --headless --path packages/game -s res://tools/models/check_glb.gd --
   res://assets/<name>/<name>.glb <Clip> ...`. It goes through the repo's own import settings
   (looping clips included) and must print `MODEL CHECK: PASS`: a skeleton with bones, every
   skinned mesh bound to it, every clip the game plays, and a centre of attack when it plays
   Attack; it lists the eyes and centres of attack. CI checks the same for every model a view
   uses (the boot flow, #992), from the clips the view lists in its `CLIPS` constant: a view that
   plays a new clip adds it there. A monster's model is worn by naming it in its species' data
   (`model`, #1223), and the boot flow checks it against the monster views' clips.
5. **In game:** first re-import after every build (`godot --headless --path packages/game
   --import`): Godot renders its imported copy of the `.glb`, and a stale one shows the previous
   build, however much the Blender checks say changed (#1164). Then, with
   `packages/game/tools/models/render_in_game.gd`, run off the desktop through
   `packages/game-offscreen/offscreen.py` (AGENTS.md's screenshot recipe; never a WSLg window), put
   the model in the game, under the game's
   cel shading and its top-down camera at play distance, on real terrain, next to the player for
   scale. Capture it at a desktop and a phone resolution. It must stand out from the ground and
   from the other monsters (colour and value contrast), including in corrupted areas. Look at the
   close-ups too: up close is how its codex page shows it. With `points`, the renders mark the
   attachment points: check each eye mark sits on its eye and the attack mark on what attacks,
   through the attack clip too.
6. **Clips in game:** a GIF of each clip playing in Godot, all of them from one run
   (`clip=Idle,Walk,Attack,...` per view: the game starts once, which is most of a run's cost),
   each made with `packages/game-models/gif.py`. Check that loops don't jump, steps don't slide, and the
   attack and hit read at game zoom.
7. **Budget:** report the triangles, bones, materials, texture sizes and `.glb` size. Medium-poly
   means a few thousand triangles for a monster (a Meshy download about 6,000, #1671); justify
   anything far above.
8. **Renderer:** check the glow and materials in the web build (Compatibility renderer) as well as
   on desktop.
9. **Ground contact:** `uv run --locked packages/game-models/blender.py --background --factory-startup
   --python packages/game-models/check_ground.py -- <model.glb>` must print `GROUND CHECK: PASS`: no paw, foot or
   any other part sinks into the ground in any frame of any clip (owner, #995). Its numbers go
   into the PR.
10. **Proportions:** the build prints `PROPORTIONS CHECK: PASS` (`lib/metrics.py`); its lines go
   into the PR. A deliberate change of proportions updates `REFERENCE` in the same PR, and the
   PR says so.
11. **Reference comparison (#1072):** `uv run --locked packages/game-models/blender.py --background
   --factory-startup --python .claude/skills/model/scripts/compare_sheet.py -- <model.glb>
   <reference> <out_dir> [views]`, the reference being the last approved `.glb` (`git show
   origin/main:packages/game/assets/<name>/<name>.glb > <scratch>/reference.glb`) or, for a new
   model, its concept image. A concept image drawn from front three-quarter (as generated ones
   usually are) is compared in the `three_quarter` view, tilted and turned to the image's angle
   when it differs: `three_quarter:<tilt>:<turn>` (#1517), or `three_quarter:fit`, which finds that
   angle itself and prints it (`COMPARE FIT`, #1531) for the PR to name. It writes `compare.png`
   (reference | ours | overlay | 128 px) and prints the silhouette match and the ten-band width
   profile per view, ending in `COMPARE CHECK: PASS` or `FAIL`. A fail is either a bug or an
   intended change of shape, which the PR names band by band.
12. **Blind rubric review (required before the first owner ping, #1072):** the builder can't see
   its own model fresh, so a **separate subagent** with no build history judges it. Copy the
   candidate's and the reference's views (`render_views.py` sheets, the `portrait` and `face`
   close-ups, the 128 px strip) into a new folder as `A-*.png` and `B-*.png`, the order decided
   by a coin flip (`python3 -c 'import random; print(random.choice("AB"))'`) and kept from the
   reviewer, so neither file name nor order says which is new. Start the subagent (the same
   model) with only that folder and this rubric, nothing about the build or the change:
   > Two versions of one game monster, A and B, are shown from every side, up close and at
   > 128 px. Judge only what you see. For each item answer "A better", "B better" or "same",
   > with a measurement in pixels or a ratio, never only an adjective: (1) eyes level, equal in
   > size and evenly spaced; (2) eyes looking forward, not cross-eyed or wall-eyed; (3) head to
   > body size; (4) the neck joins head and body smoothly; (5) legs under the body, equal
   > pairs; (6) paws on the ground; (7) nothing floating, detached or intersecting; (8) reads
   > as its creature at 128 px; (9) cute or fierce as intended, versus uncanny. Then name
   > anything that looks broken in either one, with where it is.


   Unblind its answers and put the table in the PR. Fix every item where the candidate loses,
   and treat every item where the two **measure** differently as a change to justify, whatever
   the reviewer preferred: a fresh eye measures reliably but can talk itself into liking a derp
   (on #1072 it measured close-set eyes correctly and still called them more focused). Only a
   change the owner asked for stays unfixed. A reviewer that only praises has failed: rerun it
   with a fresh subagent.
13. **Motion (required, #1071):** `uv run --locked packages/game-models/blender.py --background
   --factory-startup --python packages/game-models/check_motion.py -- <model.glb> <the speeds the build
   prints>` must print
   `MOTION CHECK: PASS`, and `packages/game-models/plot_motion.py` plots each clip the PR changes
   against the previous build (`git show main:<model.glb>`, with its `.import` beside it). Both
   go into the PR, before and after.

14. **Rebuild (#1085):** `uv run --locked --package khovax-game-models
   packages/game-models/check_rebuild.py packages/game-models/<name>.py packages/game/assets/<name>/<name>.glb` builds the model twice,
   side by side, and compares the two builds with each other and with the committed `.glb`; it
   must print `REBUILD CHECK: PASS`. On a difference it names what differs (the JSON's part, or
   each mesh's indices or attribute and each clip's channel, by how much): indices that only move
   point to a face order, values off by a hair to float noise. Run it after the last build, before
   committing the `.glb`. CI runs it with `--all` (every script named like a `.glb` under the
   game's `assets/`) whenever a model, its script or the library changes (#1161), with Blender in
   an Ubuntu 24.04 container: the C library's maths differs between releases in the last bit, and
   the decimation and face order turn that into a different file. So build committed models on
   Ubuntu 24.04 (this machine's WSL); moving to another release moves CI's container with it.
15. **Clearance (#1227):** `uv run --locked packages/game-models/blender.py --background
   --factory-startup --python packages/game-models/check_clearance.py -- <model.glb>` must print
   `CLEARANCE CHECK: PASS`: no wisp cuts into the body (crest, ears, anything) in any frame of any
   clip. A model without wisps passes. A clip that still fails waits in its `KNOWN` list with the
   issue that fixes it, and a fix takes it off. Its lines go into the PR. CI runs it on every
   `.glb` with the rebuild check (step 14).
16. **Brows (#1249):** `uv run --locked packages/game-models/blender.py --background
   --factory-startup --python packages/game-models/check_brows.py -- <model.glb>` must print
   `BROW CHECK: PASS`: no eye shows above its brow in any clip, from the front, the side or
   straight on. A model without eye points passes. Its lines go into the PR. CI runs it on every
   `.glb` with the rebuild check (step 14). `eyes.eye`'s `brow_size` makes a smaller brow that still
   covers the eye's top.
17. **Dimensions (#1299):** `uv run --locked packages/game-models/blender.py --background
   --factory-startup --python packages/game-models/check_dimensions.py -- <model.glb>` must print
   `DIMENSIONS CHECK: PASS`: every limb's segments within their body plan's ranges at rest (the
   owner, on #1297: no "weird dimensions"). A model without limbs of a known body plan passes. Its
   lines go into the PR. CI runs it on every `.glb` with the rebuild check (step 14). A new body
   plan adds its own ranges to `lib/dimensions.py`, with their reasons.

18. **Volume (#1306):** `uv run --locked packages/game-models/blender.py --background
   --factory-startup --python packages/game-models/check_volume.py -- <model.glb>` must print
   `VOLUME CHECK: PASS`: in every frame of every clip, the body's depth and width at stations
   along the spine and neck keep their share of rest (`lib/volume.py`, where the stations and
   the share are), so a creature bending down doesn't thin out (the owner, on #1305). A model
   without spine or neck bones passes. A clip that still fails waits in its `KNOWN` list with the
   issue that fixes it, and a fix takes it off. Its lines go into the PR. CI runs it on every
   `.glb` with the rebuild check (step 14).

19. **Connectivity (#1403):** `uv run --locked packages/game-models/blender.py --background
   --factory-startup --python packages/game-models/check_connectivity.py -- <model.glb>` must print
   `CONNECTIVITY CHECK: PASS`: in every frame of every clip, every attached part (crystals, gems,
   horns, claws, tufts) stays on the skin it sits on, its gap there growing no more than the
   tolerance beyond its gap at rest, and doesn't sink into it (`lib/connectivity.py`). Wisps are
   meant to float and are exempt.
   A clip that still fails waits in its `KNOWN` list with the issue that fixes it, and a fix takes it
   off. Its lines go into the PR. CI runs it on every `.glb` with the rebuild check (step 14).

20. **Footprint (#1520):** `uv run --locked packages/game-models/blender.py --background
   --factory-startup --python packages/game-models/check_footprint.py -- <model.glb>` must print
   `FOOTPRINT CHECK: PASS`. These are base rules for every monster, checked in CI (the owner, on
   #1514, #1533 and #1528), seen from above, against the hex the game stands it on:
   - **rest pose:** within its hex with 5 % padding (reach 0.95); a boss, enraged or stronger
     monster (its model in `LARGE`) may reach 5 % past it (1.05);
   - **Attack:** at most 30 % past the hex (1.30), whatever the monster;
   - **every other clip:** at most 5 % past the hex (1.05), or 10 % for a boss, enraged or
     stronger monster (1.10).
   - **a prop** (no rig, or no Walk clip: a gate, an egg), and a pack's model as its view shows
     it (#1652): 0.95 at rest and never past the hex's edge in its clips (1.00). A prop is sized against the hex and the other models, never
     against the player walking through or past it (the owner, on #1636: the gate made for the
     player to walk through was two hexes wide).

   Size the model in its script to fit. A clip that still fails waits in its `KNOWN`
   list with the issue that fixes it, and a fix takes it off. Its lines go into the PR. CI runs it
   on every `.glb` with the rebuild check (step 14).

21. **Our eyes (#1683):** `uv run --locked --package khovax-game-models
   packages/game-models/check_eyes.py` fails a creature model whose eye points have no lids, or
   that has no eyes at all: its eyes must be ours (`lib/eyes.py`, put on a generated model by
   `lib/marked_eyes.py`), never painted ones. A creature designed without eyes goes into its
   `EYELESS` list with the reason, and one still waiting for ours into `KNOWN` with its issue.
   CI runs it on every push. Its other half, `blender.py --background --factory-startup --python
   packages/game-models/check_painted_eyes.py -- <model.glb>` (#1688), fails a creature whose
   texture still shows the generator's eyes on its head: a mirrored pair of flat black or glowing
   spots that `marked_eyes.find` picks out (`DARK`, `GLOW`), left beside or under ours because
   `replace` wasn't run or missed them; and fragments of them left beyond a pair (#1756), spots
   much darker than the head's median (`marked_eyes.fragments`), which `marked_eyes.scrub` paints
   out on a head whose own colours have no dark marks. A beast whose design has small dark marks
   on its head (a stripe, a spot by the eyes) gets a `marked_eyes.Box` around each in
   `marked_eyes.MARKINGS` (#1765), with renders in its PR showing they're its design; a large dark
   area (a basalt half) needs none. CI runs it on every `.glb`, with its test
   (`test_painted_eyes.py`).

22. **Nothing covers our eyes (#1758):** `uv run --locked packages/game-models/blender.py --background
   --factory-startup --python packages/game-models/check_eyes_covered.py -- <model.glb>` must print
   `EYES COVERED CHECK: PASS`: seen straight on, no surface of the body pokes through an eye or lies
   in front of it within its rim, in any frame of any clip, its shut lid included (the owner, on
   #1747: the Wobulumu's skin crossed the bottom of its eyes). A model without eye points passes.
   `marked_eyes.replace`'s `rim=True` keeps the rim clear of the skin too when it sets the eyes
   (`clear`), and a generated model's loose pieces of skin over the eyes go with
   `marked_eyes.modelled`. A model the check still fails waits in its `KNOWN` list with the issue
   that fixes it. Its lines go into the PR. CI runs it on every `.glb`, with its test
   (`test_eyes_covered.py`).

23. **World scale (#1837):** `uv run --locked packages/game-models/blender.py --background
   --factory-startup --python packages/game-models/check_world_scale.py -- <model.glb>` must print
   `WORLD SCALE CHECK: PASS`: a model built here that isn't a monster names its kind
   (`WORLD_SCALE`) and stands, at rest, within its kind's height, and an edge piece spans its hex
   edge (`lib/world_scale.py`); the players' figure stands at the player's height; a pack's model a
   view stands on the board is held to a prop's height as the view shows it. A monster is sized
   against its hex instead (step 20), and a tile's decoration and an item aren't measured. A model
   that still fails waits in its `KNOWN` list with the issue that fixes it. Its lines go into the
   PR. CI runs it on every `.glb`, with its test (`test_world_scale.py`).

## 5. PR
- **Visuals (owner's rule), in this order:**
  1. **Every side as built:** the Blender sheet from step 1.
  2. **Every side in the game:** the same six views rendered in Godot, under the game's cel shading
     and lighting, plus the shot from the game camera at play distance (step 5).
  3. **Animations:** a GIF of each clip in the game, the attack at least; for changed clips the
     curve plots and the motion check's numbers too, before and after (step 13).
  4. **Close-ups:** the codex view, `portrait` and `face` from `render_in_game.gd`.
  Publish them on the `assets` branch per AGENTS.md.
- **One command for all of them (#1525):** `uv run --locked --package khovax-game-models
  packages/game-models/render_media.py packages/game/assets/<name>/<name>.glb --pr <n> [--tag v2]
  [--quick]` renders the sheet, the in-game shots (desktop, phone, close-ups, points, the six
  sides joined into one picture) and every clip's GIF in game and close up, Blender and Godot side
  by side and Godot off the desktop, publishes them as `pr-<n>[-<tag>]-*` and prints the
  description's media block, ready to paste. `--quick` renders only the fast-feedback pictures.
  When a render fails or hangs, the pictures that finished are still published, the block leaves
  the missing ones out and lists them with their logs, and the run exits 1 (#1694).
  It also leaves each clip's middle pose as a Blender sheet (`poses/`) and four frames of each clip
  in a row (`tiles/`) to look at; usage in its header. Run it in the background.
- **Fast feedback (owner's rule, #1047):** push the quick renders first (the Blender sheet and
  the game camera shot), put them in the description and post a comment tagging the owner
  (`@$OWNER`, the login looked up as AGENTS.md says, #1060). Then render the rest in parallel, as
  monitored background jobs, update the description again and post a second comment tagging the
  owner once every visual is in.
- **Splitting the work:** a model can come in two PRs: the model with its rig (visuals 1 and 2),
  then its clips (visual 3). Each PR shows what it adds.
- **Numbers:** the budget from step 7, the `check_glb.gd` result, the proportions (step 10), the
  comparison sheet with its numbers (step 11) and the blind review's table (step 12).
- **Review:** Codex reviews the build script's diff, never the binary.
