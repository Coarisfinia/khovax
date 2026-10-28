# Compares a model with its reference as numbers and one sheet (model skill, #1072), so a derpy
# shape shows as a measurement instead of slipping past the eye.
# Usage: uv run --locked packages/game-models/blender.py --background --factory-startup --python \
#     .claude/skills/model/scripts/compare_sheet.py -- <model.glb> <reference> <out_dir> [views]
# The reference is the last approved version of the model (a .glb, e.g. from
# `git show <commit>:packages/game/assets/<name>/<name>.glb`), rendered the same way, or a concept image (.png:
# its alpha, else everything unlike its corners, is the figure; one view only). `views` is a
# comma-separated list of front, back, left, right, top and three_quarter (default left,front,top).
# `three_quarter` is the in-game renders' three-quarter view (`render_in_game.gd`: from the
# model's front left, from above), the angle generated concept images are usually drawn from.
# Its camera can be tilted and turned to the image's: `three_quarter:<tilt>[:<turn>]`, in degrees,
# the tilt above the ground (default 31.7) and the turn from the front towards the model's left
# (default 45; 90 is the left side), e.g. `three_quarter:20:60`.
# Per view, a row of the sheet: the reference | ours | the two silhouettes overlaid | both at the
# in-game size (128 px). It prints and saves (compare.json) the silhouette match (intersection over
# union of the two silhouettes: a reference model where the shared camera puts it, a reference
# image scaled to our figure's height) and the width profile (the silhouette's width in ten bands
# from top to bottom, in the frame's height, against the reference's), and `COMPARE CHECK: PASS`
# or `FAIL` (exit 1) against the gates below.
import json
import math
import os
import sys

import blf
import bpy
import imbuf
import numpy
from mathutils import Matrix, Vector

# The gates (the sources on #1072, their detailing phase): the silhouettes overlap by at least this
# much, and no band's width is off by more than this share of the frame's height.
MIN_MATCH = 0.90
MAX_BAND = 0.03
BANDS = 10
SIZE = 512  # each render, square
GAME = 128  # the in-game size: a render scaled down to it
MEASURE_HEIGHT = 256  # silhouettes are scaled to this height before they're compared
VIEWS = {
	"front": Vector((0, -1, 0)),
	"back": Vector((0, 1, 0)),
	"left": Vector((1, 0, 0)),
	"right": Vector((-1, 0, 0)),
	"top": Vector((0, -0.001, 1)),
}
# render_in_game.gd's three_quarter, Vector3(0.8, 0.7, 0.8) in Godot's axes (y up, the model
# facing +z), is (0.8, -0.8, 0.7) in Blender's after the glTF import: tilted 31.7 degrees above the
# ground, turned 45 degrees from the front towards the model's left.
THREE_QUARTER = (math.degrees(math.atan2(0.7, math.hypot(0.8, 0.8))), 45.0)


def direction(view):
	"""Where the camera stands, seen from the model, for `view`: a name in VIEWS, or
	`three_quarter[:<tilt>[:<turn>]]`."""
	name, *angles = view.split(":")
	if name in VIEWS and not angles:
		return VIEWS[name]
	if name != "three_quarter" or len(angles) > 2:
		sys.exit("not a view: %r (%s, three_quarter or three_quarter:<tilt>[:<turn>])" % (view, ", ".join(VIEWS)))
	try:
		tilt, turn = [float(angle) for angle in angles] + list(THREE_QUARTER[len(angles):])
	except ValueError:
		sys.exit("a three_quarter view's tilt and turn are degrees: %r" % view)
	if not -90 < tilt < 90:
		sys.exit("a tilt lies between -90 and 90 degrees: %r" % view)
	tilt, turn = math.radians(tilt), math.radians(turn)
	return Vector((math.sin(turn) * math.cos(tilt), -math.cos(turn) * math.cos(tilt), math.sin(tilt)))


args = sys.argv[sys.argv.index("--") + 1:]
model_path, reference_path, out_dir = args[0], args[1], args[2]
views = (args[3] if len(args) > 3 else "left,front,top").split(",")
directions = {view: direction(view) for view in views}  # checked before Blender loads anything
reference_is_model = reference_path.lower().endswith((".glb", ".gltf"))
if not reference_is_model and len(views) != 1:
	sys.exit("a reference image shows one view: name it, e.g. `left`")
os.makedirs(out_dir, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def load(path):
	"""Imports a .glb at rest (no clip, every bone at its rest pose) and returns its meshes."""
	before = set(bpy.data.objects)
	bpy.ops.import_scene.gltf(filepath=path)
	added = [obj for obj in bpy.data.objects if obj not in before]
	shapes = set()  # the importer's bone shape (a hidden icosphere): not the model, so not framed
	for obj in added:
		if obj.type == "ARMATURE":
			shapes.update(bone.custom_shape for bone in obj.pose.bones if bone.custom_shape)
			if obj.animation_data:
				obj.animation_data.action = None
				obj.animation_data.use_nla = False
			for bone in obj.pose.bones:
				bone.matrix_basis = Matrix.Identity(4)
	return [obj for obj in added if obj.type == "MESH" and obj not in shapes]


def bounds(meshes):
	depsgraph = bpy.context.evaluated_depsgraph_get()
	lo = Vector((math.inf,) * 3)
	hi = Vector((-math.inf,) * 3)
	for obj in meshes:
		evaluated = obj.evaluated_get(depsgraph)
		for corner in evaluated.bound_box:
			world = evaluated.matrix_world @ Vector(corner)
			lo = Vector(map(min, lo, world))
			hi = Vector(map(max, hi, world))
	return lo, hi


def read(path):
	"""An image file as float RGBA rows, top row first."""
	image = bpy.data.images.load(path)
	w, h = image.size
	pixels = numpy.empty(w * h * 4, dtype=numpy.float32)
	image.pixels.foreach_get(pixels)
	bpy.data.images.remove(image)
	return pixels.reshape(h, w, 4)[::-1]


def render(meshes, others, view, name):
	"""Our flat studio render of `meshes` from `view` (the others hidden), on a clear background."""
	for obj in others:
		obj.hide_render = True
	for obj in meshes:
		obj.hide_render = False
	# A slanted camera sees the bounding box's corners spread wider than its longest side: it frames
	# the whole diagonal, so no part leaves the frame.
	camera_data.ortho_scale = (reach if view in VIEWS else (hi - lo).length) * 1.1
	camera.location = center + directions[view].normalized() * reach * 4
	camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
	scene.render.filepath = "%s/%s_%s.png" % (out_dir, name, view.replace(":", "_"))
	bpy.ops.render.render(write_still=True)
	return read(scene.render.filepath)


def figure(pixels):
	"""Where the figure is: the alpha, or for an opaque image everything unlike its corners."""
	if pixels[..., 3].min() < 0.98:
		return pixels[..., 3] > 0.5
	corners = numpy.concatenate([pixels[:8, :8], pixels[:8, -8:], pixels[-8:, :8], pixels[-8:, -8:]])
	background = corners[..., :3].reshape(-1, 3).mean(axis=0)
	return numpy.abs(pixels[..., :3] - background).max(axis=2) > 0.05


def box(mask):
	"""The rows and columns the figure spans."""
	rows, columns = numpy.nonzero(mask)
	if rows.size == 0:
		print("COMPARE CHECK: FAIL (an empty silhouette: nothing was rendered, or the image has no figure)")
		sys.exit(1)
	return slice(rows.min(), rows.max() + 1), slice(columns.min(), columns.max() + 1)


def resized(mask, height):
	"""`mask` scaled (nearest) to `height`, its aspect kept."""
	width = max(1, round(mask.shape[1] * height / mask.shape[0]))
	rows = (numpy.arange(height) * mask.shape[0] / height).astype(int)
	columns = (numpy.arange(width) * mask.shape[1] / width).astype(int)
	return mask[rows][:, columns]


def framed(theirs, ours, height):
	"""Both silhouettes on one canvas `height` tall. Two renders from one camera keep their places
	and sizes (cropped to the box around both), so only what changed differs; a reference image
	has no common frame, so each figure is cropped to itself, scaled to the height and centred."""
	if reference_is_model:
		rows, columns = box(theirs | ours)
		return resized(theirs[rows, columns], height), resized(ours[rows, columns], height)
	theirs, ours = (resized(m[box(m)], height) for m in (theirs, ours))
	width = max(theirs.shape[1], ours.shape[1])
	out = []
	for m in (theirs, ours):
		canvas = numpy.zeros((height, width), dtype=bool)
		left = (width - m.shape[1]) // 2
		canvas[:, left:left + m.shape[1]] = m
		out.append(canvas)
	return out


def profile(mask):
	"""The figure's width in each band of the canvas, top to bottom: the mean of its rows'
	extents, in the canvas's heights."""
	widths = []
	for band in numpy.array_split(mask, BANDS):
		extents = [row.nonzero()[0] for row in band]
		extents = [e[-1] - e[0] + 1 if e.size else 0 for e in extents]
		widths.append(float(numpy.mean(extents)) / mask.shape[0])
	return widths


def measure(reference_mask, model_mask):
	theirs, ours = framed(reference_mask, model_mask, MEASURE_HEIGHT)
	match = float((theirs & ours).sum() / (theirs | ours).sum())
	ours_profile, their_profile = profile(ours), profile(theirs)
	result = {
		"match": round(match, 4),
		"bands": [round(w, 4) for w in ours_profile],
		"reference_bands": [round(w, 4) for w in their_profile],
		"band_diff": [round(o - t, 4) for o, t in zip(ours_profile, their_profile)],
	}
	if reference_is_model:  # one camera for both: their sizes compare too
		(our_rows, our_columns), (their_rows, their_columns) = box(model_mask), box(reference_mask)
		result["height_ratio"] = round((our_rows.stop - our_rows.start) / (their_rows.stop - their_rows.start), 4)
		result["width_ratio"] = round((our_columns.stop - our_columns.start)
									  / (their_columns.stop - their_columns.start), 4)
	result["passed"] = match >= MIN_MATCH and all(abs(d) <= MAX_BAND for d in result["band_diff"])
	return result


def describe(view, result):
	"""The view's numbers as measurements, for the log and the sheet."""
	lines = ["%s: silhouette match %.3f (gate %.2f)" % (view, result["match"], MIN_MATCH)]
	if "height_ratio" in result:
		lines[0] += "; ours is %.0f %% of the reference's height, %.0f %% of its width" % (
			result["height_ratio"] * 100, result["width_ratio"] * 100)
	for index, (ours, theirs) in enumerate(zip(result["bands"], result["reference_bands"])):
		diff = ours - theirs
		if abs(diff) > MAX_BAND:
			share = " (%.0f %% %s)" % (abs(diff) / theirs * 100, "wider" if diff > 0 else "narrower") if theirs else ""
			lines.append("%s: band %d of %d from the top is %.3f wide, the reference %.3f%s" % (
				view, index + 1, BANDS, ours, theirs, share))
	return lines


def game_size(pixels):
	"""The render at the in-game size, averaged down, over white."""
	factor = SIZE // GAME
	small = pixels.reshape(GAME, factor, GAME, factor, 4).mean(axis=(1, 3))
	alpha = small[..., 3:4]
	return numpy.concatenate([small[..., :3] * alpha + (1 - alpha), numpy.ones_like(alpha)], axis=2)


def overlay(reference_mask, model_mask):
	"""Both silhouettes as they're compared: dark where they agree, orange only the reference's,
	blue only ours (an orange-blue pair, readable with any colour vision)."""
	height = SIZE - 64
	theirs, ours = framed(reference_mask, model_mask, height)
	if theirs.shape[1] > SIZE - 16:  # a long body: shrink both alike so it fits
		theirs, ours = framed(reference_mask, model_mask, int(height * (SIZE - 16) / theirs.shape[1]))
	tile = numpy.ones((SIZE, SIZE, 4), dtype=numpy.float32)
	top, left = (SIZE - theirs.shape[0]) // 2, (SIZE - theirs.shape[1]) // 2
	area = tile[top:top + theirs.shape[0], left:left + theirs.shape[1]]
	area[theirs & ours] = (0.2, 0.2, 0.2, 1)
	area[theirs & ~ours] = (0.95, 0.55, 0.0, 1)
	area[ours & ~theirs] = (0.0, 0.45, 0.9, 1)
	return tile


def over_grey(pixels):
	alpha = pixels[..., 3:4]
	return numpy.concatenate([pixels[..., :3] * alpha + 0.8 * (1 - alpha), numpy.ones_like(alpha)], axis=2)


def fit(pixels):
	"""A reference image letterboxed into a square tile, scaled (nearest) to fit."""
	h, w = pixels.shape[:2]
	scale = SIZE / max(h, w)
	rows = (numpy.arange(int(h * scale)) / scale).astype(int)
	columns = (numpy.arange(int(w * scale)) / scale).astype(int)
	tile = numpy.ones((SIZE, SIZE, 4), dtype=numpy.float32)
	top, left = (SIZE - rows.size) // 2, (SIZE - columns.size) // 2
	tile[top:top + rows.size, left:left + columns.size] = pixels[rows][:, columns]
	return tile


# The scene: both models at rest, framed by one orthographic camera over both, so their sizes
# compare; a flat studio render (Workbench: shapes and colours, fast) on a clear background. Its
# colours are each material's image texture, or its base colour where it has none (the hand-built
# models), so a generated model, whose colours are all in its texture, shows them too.
model = load(model_path)
reference = load(reference_path) if reference_is_model else []
lo, hi = bounds(model + reference)
center = (lo + hi) / 2
reach = max(hi - lo)
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.render.resolution_x = scene.render.resolution_y = SIZE
scene.render.film_transparent = True
camera_data = bpy.data.cameras.new("compare")
camera_data.type = "ORTHO"
camera = bpy.data.objects.new("compare", camera_data)
scene.collection.objects.link(camera)
scene.camera = camera

rows = []
results = {}
for view in views:
	ours = render(model, reference, view, "model")
	if reference_is_model:
		theirs = render(reference, model, view, "reference")
		their_tile, their_game = over_grey(theirs), game_size(theirs)
	else:
		theirs = read(reference_path)
		their_tile = fit(theirs)
		their_game = game_size(their_tile)
	results[view] = measure(figure(theirs), figure(ours))
	rows.append((view, their_tile, over_grey(ours), overlay(figure(theirs), figure(ours)), their_game,
				 game_size(ours)))

# The sheet: a row per view, a label strip over each tile and a line of numbers under the row,
# composed with numpy and labelled with Blender's own font (no ImageMagick, no system font).
GAP, STRIP, NOTE = 8, 28, 24
column = GAME + 2 * GAP
width = 3 * (SIZE + GAP) + column + GAP
row_height = STRIP + SIZE + NOTE + GAP
height = len(rows) * row_height + GAP
pixels = numpy.full((height, width, 4), (0.93, 0.93, 0.93, 1.0), dtype=numpy.float32)
labels = []
for index, (view, their_tile, our_tile, mix, their_game, our_game) in enumerate(rows):
	top = GAP + index * row_height + STRIP
	for slot, (tile, label) in enumerate(((their_tile, "reference"), (our_tile, "ours"),
										  (mix, "overlay: orange reference only, blue ours only"))):
		left = GAP + slot * (SIZE + GAP)
		pixels[top:top + SIZE, left:left + SIZE] = tile
		labels.append((left, top - 20, "%s, %s" % (view, label) if slot == 0 else label))
	left = GAP + 3 * (SIZE + GAP)
	labels.append((left, top - 20, "%d px" % GAME))
	for slot, small in enumerate((their_game, our_game)):
		pixels[top + slot * (GAME + GAP):top + slot * (GAME + GAP) + GAME, left:left + GAME] = small
	result = results[view]
	labels.append((GAP, top + SIZE + 4, "match %.3f   width bands, ours minus reference: %s" % (
		result["match"], " ".join("%+.2f" % d for d in result["band_diff"]))))

sheet_path = "%s/compare.png" % out_dir
sheet = bpy.data.images.new("compare", width, height)
sheet.pixels.foreach_set(pixels[::-1].ravel())  # Blender's rows run bottom-up
sheet.filepath_raw = sheet_path
sheet.file_format = "PNG"
sheet.save()
buffer = imbuf.load(sheet_path)
with blf.bind_imbuf(0, buffer):
	blf.size(0, 18)
	blf.color(0, 0, 0, 0, 1)
	for x, y, text in labels:
		blf.position(0, x, height - y - 16, 0)  # blf counts from the bottom
		blf.draw_buffer(0, text)
imbuf.write(buffer, filepath=sheet_path)

with open("%s/compare.json" % out_dir, "w") as out:
	json.dump(results, out, indent=1)
passed = all(result["passed"] for result in results.values())
for view, result in results.items():
	for line in describe(view, result):
		print("COMPARE", line)
	print("COMPARE", view, "width bands, ours minus reference:", result["band_diff"])
print("COMPARE SHEET", sheet_path)
print("COMPARE CHECK:", "PASS" if passed else "FAIL", "(match >= %.2f, bands within %.2f)" % (MIN_MATCH, MAX_BAND))
sys.exit(0 if passed else 1)
