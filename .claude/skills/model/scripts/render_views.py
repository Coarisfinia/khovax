# Renders a .glb from every side into one contact sheet, for the visual check (model skill).
# Usage: uv run --locked packages/game-models/blender.py --background --factory-startup --python \
#     .claude/skills/model/scripts/render_views.py -- <model.glb> <out_dir> [clips] [frames]
# Writes <out_dir>/<view>.png for front, back, left, right, top, three_quarter and sheet.png.
# `clips` is one clip or several (`Attack,Hit`), `frames` one frame (default 1) or several, as a
# list and ranges (`1,8,14`, `1-14`). One pose (one clip, one frame) writes into <out_dir> itself;
# several write each pose's views and sheet into <out_dir>/<Clip>_<frame>/ (`Attack_008`), all from
# one Blender start, which is most of a render's cost (#1050).
import math
import os
import sys

import blf
import bpy
import imbuf
import numpy
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:]
glb, out_dir = args[0], args[1]
clips = args[2].split(",") if len(args) > 2 else [""]
frames = []
for part in (args[3] if len(args) > 3 else "1").split(","):
	first, _, last = part.partition("-")
	frames.extend(range(int(first), int(last or first) + 1))
poses = [(clip, frame) for clip in clips for frame in frames]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
scene = bpy.context.scene
for clip in clips:
	if clip and clip not in bpy.data.actions:
		sys.exit(f"no clip {clip!r} in {glb}")


def pose(clip, frame):
	"""Poses the model: the named clip at the given frame, else the rest pose. The import has
	already posed the bones with a clip, and its NLA tracks would pose them again, so the NLA goes
	off and every bone starts at rest (#1079); then only the named clip moves them."""
	for obj in scene.objects:
		if obj.type != "ARMATURE":
			continue
		if obj.animation_data:
			obj.animation_data.use_nla = False
			obj.animation_data.action = bpy.data.actions.get(clip) if clip else None
		for bone in obj.pose.bones:
			bone.matrix_basis = Matrix.Identity(4)
	scene.frame_set(frame)


def bounds(floor):
	"""The model's world bounding box over every mesh, deformed, the floor left out."""
	depsgraph = bpy.context.evaluated_depsgraph_get()
	lo = Vector((math.inf,) * 3)
	hi = Vector((-math.inf,) * 3)
	for obj in scene.objects:
		if obj.type != "MESH" or obj == floor:
			continue
		evaluated = obj.evaluated_get(depsgraph)
		for corner in evaluated.bound_box:
			world = evaluated.matrix_world @ Vector(corner)
			lo = Vector(map(min, lo, world))
			hi = Vector(map(max, hi, world))
	return lo, hi


# Neutral studio: a sun for shape, a world color for fill, and per pose a grey floor for the
# silhouette.
scene.world = bpy.data.worlds.new("studio")
scene.world.color = (0.35, 0.35, 0.38)
bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), 0, math.radians(30)))
bpy.context.object.data.energy = 3.0

scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 512
scene.render.resolution_y = 512
scene.render.film_transparent = False

cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
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


def render_views(pose_dir, floor):
	"""Frames the posed model by its bounds and renders it from every view into pose_dir; returns
	the files and the floor it laid, sized to this pose."""
	lo, hi = bounds(floor)
	center = (lo + hi) / 2
	radius = max((hi - lo).length / 2, 0.01)
	if floor:
		mesh = floor.data
		bpy.data.objects.remove(floor)
		bpy.data.meshes.remove(mesh)
	bpy.ops.mesh.primitive_plane_add(size=radius * 8, location=(center.x, center.y, lo.z))
	floor = bpy.context.object
	cam_data.ortho_scale = radius * 2.4
	paths = []
	for name, direction in views.items():
		cam.location = center + direction.normalized() * radius * 4
		cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
		scene.render.filepath = f"{pose_dir}/{name}.png"
		bpy.ops.render.render(write_still=True)
		if not os.path.isfile(scene.render.filepath):
			sys.exit(f"render failed: {scene.render.filepath}")
		paths.append(scene.render.filepath)
	return paths, floor


# The sheet: tiles in a 3x2 grid, each labelled with its view, so a reviewer knows which side they
# are looking at. Composed here with numpy and Blender's own font (blf), so it needs no ImageMagick
# and no system font (#1052).
COLUMNS, GAP, STRIP = 3, 8, 32


def sheet(pose_dir, paths):
	"""Lays the view renders out into pose_dir/sheet.png."""
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
	sheet_path = f"{pose_dir}/sheet.png"
	image = bpy.data.images.new("sheet", width, height)
	image.pixels.foreach_set(pixels.ravel())
	image.filepath_raw = sheet_path
	image.file_format = "PNG"
	image.save()
	bpy.data.images.remove(image)
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


floor = None
for clip, frame in poses:
	pose_dir = out_dir if len(poses) == 1 else f"{out_dir}/{clip or 'rest'}_{frame:03d}"
	os.makedirs(pose_dir, exist_ok=True)
	pose(clip, frame)
	paths, floor = render_views(pose_dir, floor)
	sheet(pose_dir, paths)
	print("VIEWS", pose_dir)
