---
name: model
description: Build, rig, texture and verify a 3D model (monster, NPC, prop) for khovax with Blender and Godot. Use whenever a task adds or changes a .glb model, its rig, its clips or its textures.
---

# Modeling playbook (owner's way)

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
  warnings are harmless; EEVEE still renders.
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
  - `body`: soft organic bodies from metaballs (`Blob`: `ball`, `ellipsoid`, `capsule`, `limb`,
    and `tube`, one smooth tapering form along a curve, such as a tail, where a `limb`'s joints
    would bulge into beads, #1171), converted and reduced to a triangle budget.
  - `parts`: rigid pieces weighted to one bone (`part`), faceted `crystal`s (with an optional
    `curl`), curling fur `tuft`s.
  - `surface`: patterns laid on a body and bending with it: glowing `vein`s, whose loose ends
    taper out to a point (`taper`, #1171), and `rune`s (`GLYPHS`).
  - `eyes`: a detailed `eye` (eyeball, glowing iris, slit pupil, glint, glowing rim, lid), where
    it looks out from (`spot`) and which way (`look`).
  - `muzzle` (#1026): a canine `Snout`: the brow, stop, bridge and lips melted into the head's
    `Blob` (`upper`), and its own pieces (`parts`): a soft lower jaw on the jaw bone, sized as
    shares of the upper muzzle above it, the mouth's dark lining that shows when it opens, the
    nose pad and the fangs; length, taper, stop depth, lips, jaw depth and width and the chin's
    reach as parameters.
  - `quadruped`: `Proportions` and `armature` (spine, neck, head, jaw, ears, tail, four
    four-bone legs, `.L`/`.R`).
  - `weights`: `bind` (automatic weights, pieces joined in, at most four bones, normalised).
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
    #1158), `FOLLOW` (the quadruped's chains and their springs), `LEGS` (its legs for
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
- **The curve plots (#1071):** `packages/game-models/plot_motion.py -- <out.png> <Clip> <model.glb>
  [<before.glb>]` draws each bone's turn over a clip, a loop twice through with its seam
  marked, the previous build faint behind: stiffness, overlap and a stop at the seam read better
  from a curve than from a GIF.
- **The renders:** `scripts/render_views.py` (every side in Blender) and
  `packages/game/tools/models/render_in_game.gd` (any `.glb` in the real game scene: six sides,
  the game camera, the codex close-ups `portrait` and `face`, or a clip's frames; usage in its header).
- **A new model:** copy the shape of `packages/game-models/mana_wolf.py`: its proportions, its `Blob`
  body, its own parts and its palette, then `quadruped.armature`, `attachments.add`,
  `weights.bind`, `clips.animate` and `scene.export_glb`. A body plan the library lacks (a bird, a serpent)
  becomes a new library module first, then the model.

- **Running the tools** (owner's rule, #995): long-running work (Blender builds, renders, Godot
  render scripts, GIF assembly) runs in the background (`run_in_background`) and is monitored,
  never in the agent's foreground: keep working and answering messages, check the output files,
  and react when it finishes. Independent renders run in parallel (owner, #1047).

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
- **Mesh health:** apply transforms, recalculate normals outside, no loose or non-manifold geometry.
- **Reproducible (#1085):** a rebuild from an unchanged script gives the same file, byte for byte,
  so a pull request shows whether its build changed the model and two builds compare by hash.
  `scene.export_glb` puts every mesh's faces in a fixed order first (Blender's UV sphere lays out
  its faces in a different order on every run, and the exporter writes triangles in face order).
  A step that still varies between runs is a bug to fix in the library (a fixed seed, a sorted
  order), never something to commit whichever build came out. Step 14 checks it.

## 2. Rig
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
   means a few thousand triangles for a monster; justify anything far above.
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
   model, its concept image. It writes `compare.png`
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

## 5. PR
- **Visuals (owner's rule), in this order:**
  1. **Every side as built:** the Blender sheet from step 1.
  2. **Every side in the game:** the same six views rendered in Godot, under the game's cel shading
     and lighting, plus the shot from the game camera at play distance (step 5).
  3. **Animations:** a GIF of each clip in the game, the attack at least; for changed clips the
     curve plots and the motion check's numbers too, before and after (step 13).
  4. **Close-ups:** the codex view, `portrait` and `face` from `render_in_game.gd`.
  Publish them on the `assets` branch per AGENTS.md.
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
