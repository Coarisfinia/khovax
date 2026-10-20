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
  install it on Linux. Run it headless:
  `blender --background --factory-startup --python <script.py> -- <args>`
  The MESA/ZINK/EGL warnings are harmless; EEVEE still renders.
- **Godot 4.7.2**, the CI's version, for the import and in-game checks.
- **ImageMagick** (`montage`, `convert`) and `ffmpeg` for sheets and GIFs.
- The scripts beside this file: `scripts/render_views.py` (every side, one sheet) and
  `scripts/check_glb.gd` (the Godot import check).

## 1. Build (Blender script)
- **Where:** `tools/models/<name>.py` builds the model, and `assets/<name>/<name>.glb` is its output,
  with `SOURCE.md`, a license and a `CREDITS.md` entry, as AGENTS.md's asset rules say.
- **Look:** cel-shaded eye candy, medium-poly for anything the camera sees up close (AGENTS.md,
  #69). It must read from the game's top-down camera, so the shape comes from the silhouette
  first and the detail second.
- **Scale and placement:** the origin at the feet, facing Godot's forward (-Z after import), the
  height matching the model it sits beside in the game (measure the reference .glb).
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

## 3. Textures and materials
- **Few materials:** at most about four per model, and one texture atlas where possible
  (≤ 1024², power of two) so it stays cheap on mobile and web.
- **Shading:** flat or ramp-friendly colours that survive the game's cel shading; a glow via an
  emissive colour, which the Compatibility renderer shows on web and Android too.
- **Export:** `bpy.ops.export_scene.gltf(filepath=..., export_format='GLB', export_animations=True,
  export_skins=True)`, then commit the `.glb` and its `.import`, with looping clips set to loop
  there (as `Rogue.glb.import` does).

## 4. Verify (every item gives an image or a number for the PR)
1. **Every side:** `blender --background --factory-startup --python
   .claude/skills/model/scripts/render_views.py -- <model.glb> <out_dir> [clip] [frame]`. It
   writes front, back, left, right, top and a three-quarter view, and `sheet.png`. **Look at it.**
   Check the proportions, gaps, stretched textures and anything floating or clipping.
2. **Deformation stress:** render the extreme frames of each clip, plus a pose with each major
   bone bent ±45°. Joints must not collapse or tear.
3. **Silhouette:** a flat black render from the game camera's angle. Is it readable as what it
   is, at the size it has on screen?
4. **Godot import:** copy the `.glb` into a scratch project and run
   `godot --headless --path <project> -s check_glb.gd -- <model.glb> <Clip> ...`. It must print
   `MODEL CHECK: PASS`: a skeleton, a skinned mesh and every clip the game plays.
5. **In game:** use AGENTS.md's screenshot recipe to put the model in the game, under the game's
   cel shading and its top-down camera at play distance, on real terrain, next to the player for
   scale. Capture it at a desktop and a phone resolution. It must stand out from the ground and
   from the other monsters (colour and value contrast), including in corrupted areas.
6. **Clips in game:** a GIF of each clip playing in Godot. Check that loops don't jump, steps don't
   slide, and the attack and hit read at game zoom.
7. **Budget:** report the triangles, bones, materials, texture sizes and `.glb` size. Medium-poly
   means a few thousand triangles for a monster; justify anything far above.
8. **Renderer:** check the glow and materials in the web build (Compatibility renderer) as well as
   on desktop.

## 5. PR
- **Visuals (owner's rule):** the side sheet, the silhouette, the in-game shots and the clip GIFs,
  published on the `assets` branch per AGENTS.md.
- **Numbers:** the budget from step 7, and the `check_glb.gd` result.
- **Review:** Codex reviews the build script's diff, never the binary.
