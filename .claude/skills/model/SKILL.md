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
  install it on Linux. Run it headless, through `tools/models/blender.sh`:
  `tools/models/blender.sh --background --factory-startup --python <script.py> -- <args>`
  The wrapper puts Blender on the GPU under WSL (`GALLIUM_DRIVER=d3d12`, #1050), for that process
  only: Mesa's default falls back to the CPU's software rasteriser. (On the owner's laptop,
  `blender` on the PATH is such a wrapper already; `blender.sh` is for every other machine.)
  Never set it for the shell:
  Godot would pick it up, and on d3d12 its renderer breaks every skinned mesh. The MESA/ZINK/EGL
  warnings are harmless; EEVEE still renders.
- **Godot 4.7.2**, the CI's version: every Godot check runs in the game project itself, never in
  a scratch project, so the repo's import settings apply. It renders on the CPU (the software
  rasteriser), so `render_in_game.gd` turns off vsync and the frame cap itself: no waiting for
  the screen between frames. Blender (GPU) and Godot (CPU) renders don't compete and
  run side by side; several Godot renders at once only share the CPU's cores.
- **ffmpeg** for GIFs through
  `uv run --locked tools/models/gif.py <frame_dir> <Clip>` (a palette pass, looping; options in its
  header), never a hand-typed command.
- The scripts beside this file: `scripts/render_views.py` (every side, one labelled sheet, drawn
  in Blender with its own font: no ImageMagick, no system font) and
  `scripts/check_glb.gd` (the Godot import check).

## Shared library and tools (owner's rule, #995)
**Tools are built reusable; a model script holds only that model's parameters and parts.** Anything
a second model could use goes into the library or a generic tool, never into one model's script.

- **The Blender library, `tools/models/lib/`** (a model script imports it after
  `sys.path.insert(0, <tools/models>)`):
  - `scene`: a clean scene at the clip rate, `apply_scale`, `triangles`, and `export_glb` (the
    export settings the game takes: GLB, skins, one animation per NLA track, Y up).
  - `materials`: cel-friendly flat colours and emissive glows (`palette`).
  - `body`: soft organic bodies from metaballs (`Blob`: `ball`, `ellipsoid`, `capsule`, `limb`),
    converted and reduced to a triangle budget.
  - `parts`: rigid pieces weighted to one bone (`part`), faceted `crystal`s (with an optional
    `curl`), curling fur `tuft`s.
  - `surface`: patterns laid on a body and bending with it: glowing `vein`s and `rune`s (`GLYPHS`).
  - `eyes`: a detailed `eye` (eyeball, glowing iris, slit pupil, glint, glowing rim, lid).
  - `quadruped`: `Proportions` and `armature` (spine, neck, head, jaw, ears, tail, four
    four-bone legs, `.L`/`.R`).
  - `weights`: `bind` (automatic weights, pieces joined in, at most four bones, normalised).
  - `clips`: `cycle_frames` (gait timing from the game's speed), `gait`, the quadruped set
    (`idle`, `attack`, `hit`, `faint`) and `animate` (keys and stashes every clip, and with
    `ground_meshes` lifts the root wherever a pose sinks into the ground).
  - `ground`: ground contact (`lowest`, `settle`, `report`).
  - `symmetry`: `check` fails the build when a left part (`.L`) isn't its right twin (`.R`)
    mirrored across X; a model script runs it on its parts before they're joined.
  - `parts.claws`: claws fanned out along a paw's front like toes, the middle ones longer, curving
    down; count, spread, size, fan and curl as parameters.
  - `attachments`: `add` gives the rig its attachment points (below), each a small bone that
    deforms nothing, parented to the bone it moves with; `eyes.spot` is where an eye looks out.
- **The ground check:** `tools/models/check_ground.py -- <model.glb> [tolerance]` samples every
  frame of every clip and prints, per clip, the lowest point of the deformed mesh and of each
  paw or foot; it fails when anything sinks below the ground (z = 0) by more than the tolerance.
- **The renders:** `scripts/render_views.py` (every side in Blender) and
  `tools/models/render_in_game.gd` (any `.glb` in the real game scene: six sides, the game
  camera, the codex close-ups `portrait` and `face`, or a clip's frames; usage in its header).
- **A new model:** copy the shape of `tools/models/mana_wolf.py`: its proportions, its `Blob`
  body, its own parts and its palette, then `quadruped.armature`, `attachments.add`,
  `weights.bind`, `clips.animate` and `scene.export_glb`. A body plan the library lacks (a bird, a serpent)
  becomes a new library module first, then the model.

- **Running the tools** (owner's rule, #995): long-running work (Blender builds, renders, Godot
  render scripts, GIF assembly) runs in the background (`run_in_background`) and is monitored,
  never in the agent's foreground: keep working and answering messages, check the output files,
  and react when it finishes. Independent renders run in parallel (owner, #1047).

## 1. Build (Blender script)
- **Where:** `tools/models/<name>.py` builds the model, and `assets/<name>/<name>.glb` is its output,
  with `SOURCE.md`, a license and a `CREDITS.md` entry, as AGENTS.md's asset rules say.
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
  matches or exceeds it up close (owner). Its build script, `tools/models/mana_wolf.py`, and its
  renders on the `assets` branch (`pr-995-v2-*`, the close-ups `pr-995-v2-portrait.png` and
  `pr-995-v2-face.png` first) are the reference.
- **Scale and placement:** the origin at the feet, facing +Z after import (glTF's forward,
  Blender's -Y; `Vector3.MODEL_FRONT`), like every model in the game: the views turn a figure with
  `atan2(heading.x, heading.z)`, so one built facing -Z walks backwards. The height matches the
  model it sits beside in the game (measure the reference .glb).
- **Mesh health:** apply transforms, recalculate normals outside, no loose or non-manifold geometry.

## 2. Rig
- **Armature:** a full chain per limb (at least three bones per leg), spine, neck, head, jaw where
  it has one, tail and ear chains where it has them. Bones named left/right with `.L`/`.R`.
- **Weights:** automatic weights (`ARMATURE_AUTO`) as a start, then fix by script where they
  fail. At most four bone influences per vertex, normalised.
- **Clips:** one action per state the game plays. Read the view that will use it and the clip
  names of the model it replaces, and cover each (e.g. Idle, Walk, Run, Attack, Hit, Death).
  Looping clips start and end on the same pose, and the walk speed matches how fast the game
  moves the entity (no foot sliding).

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
1. **Every side:** `tools/models/blender.sh --background --factory-startup --python
   .claude/skills/model/scripts/render_views.py -- <model.glb> <out_dir> [clip] [frame]`. It
   writes front, back, left, right, top and a three-quarter view, and `sheet.png`. **Look at it.**
   Check the proportions, gaps, stretched textures and anything floating or clipping.
2. **Deformation stress:** render the extreme frames of each clip, plus a pose with each major
   bone bent ±45°. Joints must not collapse or tear.
3. **Silhouette:** a flat black render from the game camera's angle. Is it readable as what it
   is, at the size it has on screen?
4. **Godot import, in the game project:** after `godot --headless --path . --import`, run
   `godot --headless --path . -s res://.claude/skills/model/scripts/check_glb.gd --
   res://assets/<name>/<name>.glb <Clip> ...`. It goes through the repo's own import settings
   (looping clips included) and must print `MODEL CHECK: PASS`: a skeleton with bones, every
   skinned mesh bound to it, every clip the game plays, and a centre of attack when it plays
   Attack; it lists the eyes and centres of attack. CI checks the same for every model a view
   uses (the boot flow, #992), from the clips the view lists in its `CLIPS` constant: a view that
   plays a new clip adds it there.
5. **In game:** with `tools/models/render_in_game.gd` and AGENTS.md's hidden-window recipe, put
   the model in the game, under the game's
   cel shading and its top-down camera at play distance, on real terrain, next to the player for
   scale. Capture it at a desktop and a phone resolution. It must stand out from the ground and
   from the other monsters (colour and value contrast), including in corrupted areas. Look at the
   close-ups too: up close is how its codex page shows it. With `points`, the renders mark the
   attachment points: check each eye mark sits on its eye and the attack mark on what attacks,
   through the attack clip too.
6. **Clips in game:** a GIF of each clip playing in Godot. Check that loops don't jump, steps don't
   slide, and the attack and hit read at game zoom.
7. **Budget:** report the triangles, bones, materials, texture sizes and `.glb` size. Medium-poly
   means a few thousand triangles for a monster; justify anything far above.
8. **Renderer:** check the glow and materials in the web build (Compatibility renderer) as well as
   on desktop.
9. **Ground contact:** `tools/models/blender.sh --background --factory-startup --python
   tools/models/check_ground.py -- <model.glb>` must print `GROUND CHECK: PASS`: no paw, foot or
   any other part sinks into the ground in any frame of any clip (owner, #995). Its numbers go
   into the PR.

## 5. PR
- **Visuals (owner's rule), in this order:**
  1. **Every side as built:** the Blender sheet from step 1.
  2. **Every side in the game:** the same six views rendered in Godot, under the game's cel shading
     and lighting, plus the shot from the game camera at play distance (step 5).
  3. **Animations:** a GIF of each clip in the game, the attack at least.
  4. **Close-ups:** the codex view, `portrait` and `face` from `render_in_game.gd`.
  Publish them on the `assets` branch per AGENTS.md.
- **Fast feedback (owner's rule, #1047):** push the quick renders first (the Blender sheet and
  the game camera shot), put them in the description and post a comment tagging the owner
  (`@$OWNER`, the login looked up as AGENTS.md says, #1060). Then render the rest in parallel, as
  monitored background jobs, update the description again and post a second comment tagging the
  owner once every visual is in.
- **Splitting the work:** a model can come in two PRs: the model with its rig (visuals 1 and 2),
  then its clips (visual 3). Each PR shows what it adds.
- **Numbers:** the budget from step 7, and the `check_glb.gd` result.
- **Review:** Codex reviews the build script's diff, never the binary.
