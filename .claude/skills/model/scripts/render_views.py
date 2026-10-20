# Renders a .glb from every side into one contact sheet, for the visual check (model skill).
# Usage: blender --background --factory-startup --python render_views.py -- <model.glb> <out_dir> [clip] [frame]
# Writes <out_dir>/<view>.png for front, back, left, right, top, three_quarter and sheet.png.
import math
import os
import subprocess
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
glb, out_dir = args[0], args[1]
clip = args[2] if len(args) > 2 else ""
frame = int(args[3]) if len(args) > 3 else 1
os.makedirs(out_dir, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
scene = bpy.context.scene

# Pose: the named clip at the given frame, else the rest pose.
for obj in scene.objects:
	if obj.type == "ARMATURE" and obj.animation_data:
		action = bpy.data.actions.get(clip) if clip else None
		obj.animation_data.action = action
scene.frame_set(frame)

# Frame the model: its world bounding box over every mesh, deformed.
depsgraph = bpy.context.evaluated_depsgraph_get()
lo = Vector((math.inf,) * 3)
hi = Vector((-math.inf,) * 3)
for obj in scene.objects:
	if obj.type != "MESH":
		continue
	evaluated = obj.evaluated_get(depsgraph)
	for corner in evaluated.bound_box:
		world = evaluated.matrix_world @ Vector(corner)
		lo = Vector(map(min, lo, world))
		hi = Vector(map(max, hi, world))
center = (lo + hi) / 2
radius = max((hi - lo).length / 2, 0.01)

# Neutral studio: a sun for shape, a world color for fill, a grey floor for the silhouette.
scene.world = bpy.data.worlds.new("studio")
scene.world.color = (0.35, 0.35, 0.38)
bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), 0, math.radians(30)))
bpy.context.object.data.energy = 3.0
bpy.ops.mesh.primitive_plane_add(size=radius * 8, location=(center.x, center.y, lo.z))

scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 512
scene.render.resolution_y = 512
scene.render.film_transparent = False

cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = radius * 2.4
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

# glTF's forward is -Y in Blender after import: "front" looks at the model's face.
views = {
	"front": Vector((0, -1, 0)),
	"back": Vector((0, 1, 0)),
	"left": Vector((-1, 0, 0)),
	"right": Vector((1, 0, 0)),
	"top": Vector((0, -0.001, 1)),
	"three_quarter": Vector((1, -1, 0.8)),
}
paths = []
for name, direction in views.items():
	cam.location = center + direction.normalized() * radius * 4
	cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
	scene.render.filepath = f"{out_dir}/{name}.png"
	bpy.ops.render.render(write_still=True)
	if not os.path.isfile(scene.render.filepath):
		sys.exit(f"render failed: {scene.render.filepath}")
	paths.append(scene.render.filepath)

# Each tile labelled with its view, so a reviewer knows which side they're looking at.
labelled = [part for path in paths for part in ("-label", path.split("/")[-1][:-4], path)]
subprocess.run(["montage", *labelled, "-tile", "3x2", "-geometry", "+4+4", "-pointsize", "20",
	f"{out_dir}/sheet.png"], check=True)
print("VIEWS", out_dir)
