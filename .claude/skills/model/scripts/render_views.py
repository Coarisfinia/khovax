# Renders a .glb from every side into one contact sheet, for the visual check (model skill).
# Usage: tools/models/blender.sh --background --factory-startup --python \
#     .claude/skills/model/scripts/render_views.py -- <model.glb> <out_dir> [clip] [frame]
# Writes <out_dir>/<view>.png for front, back, left, right, top, three_quarter and sheet.png.
import math
import os
import sys

import blf
import bpy
import imbuf
import numpy
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

# glTF's forward (+Z, the game's model front) is -Y in Blender after import: "front" looks at the
# model's face. "left" and "right" are the model's own sides, so its left is +X.
views = {
	"front": Vector((0, -1, 0)),
	"back": Vector((0, 1, 0)),
	"left": Vector((1, 0, 0)),
	"right": Vector((-1, 0, 0)),
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

# The sheet: tiles in a 3x2 grid, each labelled with its view, so a reviewer knows which side they
# are looking at. Composed here with numpy and Blender's own font (blf), so it needs no ImageMagick
# and no system font (#1052).
COLUMNS, GAP, STRIP = 3, 8, 32
tiles = [bpy.data.images.load(path) for path in paths]  # their real size, whatever the scale
tile_w = max(tile.size[0] for tile in tiles)
tile_h = max(tile.size[1] for tile in tiles)
rows = math.ceil(len(paths) / COLUMNS)
width = COLUMNS * (tile_w + GAP) + GAP
height = rows * (tile_h + STRIP + GAP) + GAP
pixels = numpy.ones((height, width, 4), dtype=numpy.float32)  # white, rows bottom-up like Blender's
spots = []
for index, tile in enumerate(tiles):
	w, h = tile.size
	tile_pixels = numpy.empty(w * h * 4, dtype=numpy.float32)
	tile.pixels.foreach_get(tile_pixels)
	bpy.data.images.remove(tile)
	x = GAP + (index % COLUMNS) * (tile_w + GAP)
	y = height - (index // COLUMNS + 1) * (tile_h + STRIP + GAP)  # the label strip lies under the tile
	pixels[y + STRIP:y + STRIP + h, x:x + w] = tile_pixels.reshape(h, w, 4)
	spots.append((x, y))
sheet_path = f"{out_dir}/sheet.png"
sheet = bpy.data.images.new("sheet", width, height)
sheet.pixels.foreach_set(pixels.ravel())
sheet.filepath_raw = sheet_path
sheet.file_format = "PNG"
sheet.save()
sheet_buffer = imbuf.load(sheet_path)
with blf.bind_imbuf(0, sheet_buffer):
	blf.size(0, 20)
	blf.color(0, 0, 0, 0, 1)
	for path, (x, y) in zip(paths, spots):
		label = os.path.basename(path)[:-4]
		label_width, _ = blf.dimensions(0, label)
		blf.position(0, x + (tile_w - label_width) / 2, y + 9, 0)
		blf.draw_buffer(0, label)
imbuf.write(sheet_buffer, filepath=sheet_path)
print("VIEWS", out_dir)
