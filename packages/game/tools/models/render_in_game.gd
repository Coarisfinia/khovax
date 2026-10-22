# gdstyle:ignore-file=quality/no-debug-print
# The tool reports what it wrote on stdout; that is what it is for.
extends SceneTree
## Renders a model inside the real game (the model skill's in-game check, #990): the main scene
## runs in a SubViewport, under the game's cel shading, ink outline and sun, and the model stands
## on the tile beside the player, idling. It writes the model from six sides (front, back, left,
## right, top, three-quarter), the shot from the game camera at play distance, and two close-ups
## on a bare background as its codex page shows it full-screen (#995): the whole model
## ("portrait") and its head and chest ("face"). Given clips, it writes each clip's frames
## for a GIF instead, at the clip's own rate, from the game camera or from any of those views. Any
## model works: the cameras frame it by its bounds, the close-ups by its outline, and a clip's by
## where it moves over the clip. With `points`, it marks the model's
## attachment points
## (PointMarks, #1007). Its eyes glow as in the game (EyeGlow, #1008), calm, or agitated with
## `agitated`; an Attack clip's frames flare the glow as the game does when it strikes. With
## `type=<type>` they glow in that type's colour (TypeGlow), and with `leaning=<path>` in the shape
## of a player's leaning toward that path (#1063).
##
## Render it off the desktop and silent, as AGENTS.md's screenshot recipe says:
##   uv run --locked packages/game-offscreen/offscreen.py -- --path packages/game \
##     -s res://tools/models/render_in_game.gd -- \
##     res://assets/<name>/<name>.glb <out_dir> [size=1280x720] \
##     [clip=<Clip>[,<Clip>...] [from=<view>]] [points] [agitated] [type=<type>] \
##     [leaning=harmony|supremacy] \
##     --seed=0 --user-dir=<branch>
## The launch options after it (LaunchOptions) start the world as the game would.

## Frames the game draws before the first capture: shaders compile and the fog eases open.
const SETTLE_FRAMES: int = 90
## The cameras' field of view, and how much room they leave around what they frame.
const FOV: float = 35.0
const MARGIN: float = 1.08
## Where each camera stands, seen from the model, which faces +Z like every model in the game.
const VIEWS: Dictionary[String, Vector3] = {
	"front": Vector3(0.0, 0.25, 1.0),
	"back": Vector3(0.0, 0.25, -1.0),
	"left": Vector3(1.0, 0.25, 0.0),
	"right": Vector3(-1.0, 0.25, 0.0),
	"top": Vector3(0.0, 1.0, 0.01),
	"three_quarter": Vector3(0.8, 0.7, 0.8),
	"portrait": Vector3(0.75, 0.35, 1.0),
	"face": Vector3(0.6, 0.25, 1.0),
}
## The close-ups, on a bare background: no ground under them.
const CLOSE_UPS: Array[String] = ["portrait", "face"]
## What close-ups keep of the main scene: the game's sun, ink outline and graphics settings.
const KEPT_IN_CLOSE_UPS: Array[String] = ["Driver", "Sun", "InkOutline", "Graphics"]
## The face close-up frames what lies within this share of the model's height of its head bone:
## the head and the chest. A model without one frames this share of its length at its front end,
## and of its height at the top.
const FACE_SHARE: float = 0.4
## What the side shots keep of the instance: only the ground. The HUD, the player, the people,
## the other monsters and the trees would stand between the camera and the model.
const KEPT_IN_SIDES: String = "HexGrid"
## A clip's frame rate when the model's import doesn't give one: Godot's import default.
const DEFAULT_FPS: float = 30.0
## Frames to wait after posing a shot before capturing it, so the pose has been drawn.
const DRAW_FRAMES: int = 2

var _viewport: SubViewport
var _main: Node3D
var _out_dir: String = ""
var _clip: String = ""
## Where a clip is seen from: "game" (the game camera) or one of VIEWS.
var _from: String = "game"
var _frame: int = 0
var _wait: int = 0
## The shots to take, in order: each one's file name, and what poses the scene for it.
var _names: Array[String] = []
var _poses: Array[Callable] = []
var _current: int = -1
var _piece: HexPiece
var _side_camera: Camera3D
var _game_camera: Camera3D
## The model's bounds in the world, standing at rest.
var _bounds: AABB
## What each close-up frames: the model's vertices in the world, standing at rest, all of them
## or its face's. The close-ups frame their outline, which fills far less of the frame than the
## bounds' corners do from an angle (#1004).
var _close_ups: Dictionary[String, PackedVector3Array] = {}


## One step a frame: settle, place the model, then pose, draw and capture each shot in turn.
func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == SETTLE_FRAMES:
		_place()
	if _frame <= SETTLE_FRAMES:
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _current >= 0 and not _saved(_names[_current]):
		quit(1)
		return true
	_current += 1
	if _current >= _names.size():
		var spot: Vector2 = _game_camera.unproject_position(_piece.global_position)
		print("MODEL ON SCREEN AT ", Vector2i(spot))
		return true
	_poses[_current].call()
	_wait = DRAW_FRAMES
	return false


func _initialize() -> void:
	# Godot's Wayland display server can hang on exit (#1021): it wakes its event thread with a
	# roundtrip, but when that thread isn't polling yet, the main thread reads the reply itself and
	# then waits for ever for the thread, which polls for a reply that already came. Refused at
	# once, and killed rather than quit, since quitting is what can hang.
	if DisplayServer.get_name() == "Wayland":
		printerr("Wayland can hang on exit: render through packages/game-offscreen/offscreen.py")
		var _killed: Error = OS.kill(OS.get_process_id())
	# It renders on the CPU, so it draws each frame as soon as it can, never waiting for the
	# screen (#1050): no vsync and no frame cap, whatever the command line says.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var problem: String = LaunchOptions.parse(args).apply()
	var size: Vector2i = Vector2i(1280, 720)
	for arg: String in args.slice(2):
		if arg.begins_with("size="):
			var parts: PackedStringArray = arg.trim_prefix("size=").split("x")
			size = Vector2i(parts[0].to_int(), parts[1].to_int())
		elif arg.begins_with("clip="):
			_clip = arg.trim_prefix("clip=")
		elif arg.begins_with("from="):
			_from = arg.trim_prefix("from=")
	if problem.is_empty() and not (_from == "game" or VIEWS.has(_from)):
		problem = "no view " + _from
	if problem.is_empty() and args.size() >= 2:
		_out_dir = args[1]
		var made: Error = DirAccess.make_dir_recursive_absolute(_out_dir)
		if made != OK:
			problem = "can't make %s: %s" % [_out_dir, error_string(made)]
	if args.size() < 2 or not problem.is_empty():
		printerr("usage: -- res://<model>.glb <out_dir> [size=WxH] [clip=<Clip>]; ", problem)
		quit(1)
		return
	_viewport = SubViewport.new()
	_viewport.size = size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(_viewport)
	_main = (load(Boot.GAME) as PackedScene).instantiate() as Node3D
	# No music: a render is silent, and a track still playing when the run quits can outlive the
	# tree, since the audio server frees a stopped track only on a later mix (#1093). Godot then
	# sometimes reports it as resources still in use at exit.
	_main.get_node("Music").free()
	_viewport.add_child(_main)


## Stands the model on the tile beside the player and lists the shots.
func _place() -> void:
	var driver: GameDriver = _main.get_node("Driver") as GameDriver
	_piece = HexPiece.new()
	_piece.base_offset = 0.0
	var model: Node3D = (load(OS.get_cmdline_user_args()[0]) as PackedScene).instantiate() as Node3D
	Toon.apply_to_model(model)
	var glow: EyeGlow = EyeGlow.add_to(model)
	_glow_as_asked(glow)
	_piece.add_child(model)
	_main.add_child(_piece)
	_piece.tile = _beside(driver.state, driver.state.player(0).tile)
	var animations: AnimationPlayer = model.find_child("AnimationPlayer") as AnimationPlayer
	_game_camera = _main.get_node("Camera3D") as Camera3D
	_side_camera = Camera3D.new()
	_main.add_child(_side_camera)
	_side_camera.fov = FOV
	_bounds = _bounds_of(model)
	var points: PackedVector3Array = _points_of(model)
	var face: PackedVector3Array = PackedVector3Array(Array(points).filter(_in_face(model)))
	# A model without vertices is framed by its bounds' corners, and a face without any by all of
	# it.
	if points.is_empty():
		points = _corners(_bounds)
	_close_ups = { "portrait": points, "face": points if face.is_empty() else face }
	if OS.get_cmdline_user_args().has("points"):
		_piece.add_child(PointMarks.new(model, _bounds.size.y))
	if _clip.is_empty():
		animations.play(&"Idle")
		_add_shot("game", _game_camera.make_current)
		for side: String in VIEWS:
			_add_shot(side, _pose_side.bind(side))
		return
	if VIEWS.has(_from):
		_show_alone(_from)
	else:
		_game_camera.make_current()
	# The glow moves on with the clips' frames, not with how long the frames take to draw.
	glow.process_mode = Node.PROCESS_MODE_DISABLED
	_add_clip_shots(model, animations, glow)


## Lists every frame of every clip `_clip` names, or ends the run when the model lacks one.
## Several clips in one run (#1050): the game starts once for all of them, which is most of what a
## run costs.
func _add_clip_shots(model: Node3D, animations: AnimationPlayer, glow: EyeGlow) -> void:
	var clips: PackedStringArray = _clip.split(",")
	for clip: String in clips:
		if not animations.has_animation(StringName(clip)):
			var known: PackedStringArray = animations.get_animation_list()
			printerr("the model has no clip %s: it has %s" % [clip, known])
			quit(1)
			return
	var fps: float = _clip_fps()
	for clip: String in clips:
		var times: PackedFloat32Array = _frame_times(
			animations.get_animation(StringName(clip)),
			fps,
		)
		# A view's camera frames where the model moves over the whole clip, set on its first frame
		# and kept for the rest; the game camera stays where the game has it.
		var framed: PackedVector3Array = []
		if VIEWS.has(_from):
			framed = _posed_over(model, animations, clip, times)
		for frame: int in times.size():
			var pose: Callable = _pose_clip.bind(animations, glow, clip, times[frame], framed)
			_add_shot("%s_%03d" % [clip, frame], pose)
			framed = []


## The rate the model's clips are imported at, as its `.import` gives it: their frames are captured
## at it, so every keyed frame is in the GIF (#1150).
func _clip_fps() -> float:
	var import: ConfigFile = ConfigFile.new()
	if import.load(OS.get_cmdline_user_args()[0] + ".import") != OK:
		return DEFAULT_FPS
	return float(import.get_value("params", "animation/fps", DEFAULT_FPS))


## When in `animation` each of its frames is captured, `fps` a second. A looping clip ends on its
## first pose again, so its frames stop short of the end and are spaced evenly over one cycle: a
## frame at the end would show the first pose twice, a hold at the GIF's seam the game never plays
## (#1089). A one-shot keeps its last pose.
func _frame_times(animation: Animation, fps: float) -> PackedFloat32Array:
	var length: float = animation.length
	var looping: bool = animation.loop_mode != Animation.LOOP_NONE
	var frames: int = maxi(1, roundi(length * fps)) if looping else ceili(length * fps) + 1
	var times: PackedFloat32Array = []
	for frame: int in frames:
		var _added: bool = times.append(
			frame * length / frames if looping else minf(frame / fps, length),
		)
	return times


## Where `model`'s vertices pass over `clip` at `times`: all of them, or the face's for the face
## close-up. Framing these rather than the resting outline keeps a lunge in the frame (#1148).
func _posed_over(
		model: Node3D,
		animations: AnimationPlayer,
		clip: String,
		times: PackedFloat32Array,
) -> PackedVector3Array:
	animations.play(StringName(clip))
	animations.pause()
	var points: PackedVector3Array = []
	for time: float in times:
		animations.seek(time, true)
		var posed: PackedVector3Array = _points_of(model)
		if _from == "face":
			var face: PackedVector3Array = PackedVector3Array(Array(posed).filter(_in_face(model)))
			posed = posed if face.is_empty() else face
		points.append_array(posed)
	return _corners(_bounds) if points.is_empty() else points


## Makes `glow` agitated, in a type's colour or in a leaning's shape as the command line asks.
func _glow_as_asked(glow: EyeGlow) -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "agitated":
			glow.agitated = true
			glow.brightness = EyeGlow.AGITATED
		elif arg.begins_with("type="):
			var family: int = TypeChart.family_of(arg.trim_prefix("type="))
			glow.color = TypeGlow.COLORS[family] if family >= 0 else EyeGlow.COLOR
		elif arg.begins_with("leaning="):
			glow.leaning = arg.trim_prefix("leaning=")


## Poses `clip` at `time`, and the `glow` in the model's eyes with it. Its first frame starts the
## clip, aims the camera at what it `framed` (unless that's empty), and flares an Attack's glow, as
## the game does when the monster strikes.
func _pose_clip(
		animations: AnimationPlayer,
		glow: EyeGlow,
		clip: String,
		time: float,
		framed: PackedVector3Array,
) -> void:
	if not framed.is_empty():
		_aim_side(_from, framed)
	if is_zero_approx(time):
		animations.play(StringName(clip))
		animations.pause()
		glow.flare_left = 0.0
		if clip == "Attack":
			glow.flare()
	# The glow moves on by as much of the clip as passed since the last frame.
	var step: float = 0.0 if is_zero_approx(time) else time - animations.current_animation_position
	animations.seek(time, true)
	glow.advance(step)
	glow.place()


## Saves what the viewport shows as `file`, and whether that worked.
func _saved(file: String) -> bool:
	var path: String = _out_dir.path_join(file + ".png")
	var error: Error = _viewport.get_texture().get_image().save_png(path)
	print("WROTE " if error == OK else "COULDN'T WRITE ", path)
	return error == OK


func _add_shot(file: String, pose: Callable) -> void:
	_names.append(file)
	_poses.append(pose)


## A tile next to `tile` that the region has, so the model stands on ground beside the player.
func _beside(state: GameState, tile: Vector2i) -> Vector2i:
	for direction: Vector2i in Hex.DIRECTIONS:
		if state.region.has_tile(tile + direction):
			return tile + direction
	return tile


## Looks at the model from `side` (VIEWS), framing all of it (or its face), alone on bare
## ground, or on nothing at all for a close-up.
func _pose_side(side: String) -> void:
	_show_alone(side)
	_aim_side(side, _close_ups[side] if CLOSE_UPS.has(side) else _corners(_bounds))


## Shows the model alone for `side` (VIEWS), through the side camera: on bare ground, or on
## nothing at all for a close-up.
func _show_alone(side: String) -> void:
	var hidden: Array[Node] = _main.get_node("Instance").get_children()
	if CLOSE_UPS.has(side):
		hidden = _main.get_children().filter(_hidden_in_close_ups)
	hidden.append(_main.get_node("Hud"))
	for node: Node in hidden:
		var kept: bool = node.name == KEPT_IN_SIDES and not CLOSE_UPS.has(side)
		# Stopped too, so a view that shows its node each frame doesn't show it again.
		node.process_mode = Node.PROCESS_MODE_INHERIT if kept else Node.PROCESS_MODE_DISABLED
		node.set("visible", kept)
	_side_camera.make_current()


## Aims the side camera from `side` (VIEWS) at `points`: a close-up at their outline, any other
## side at their bounds' corners.
func _aim_side(side: String, points: PackedVector3Array) -> void:
	if CLOSE_UPS.has(side):
		_aim(points, VIEWS[side], Vector3.UP, MARGIN)
		return
	var up: Vector3 = Vector3.FORWARD if side == "top" else Vector3.UP
	_aim(_corners(_box_of(points)), VIEWS[side], up, MARGIN)


## Points the camera from `direction` at `points`, so their outline sits in the middle of the
## frame and fills it but for `margin`. A few passes: each centres the outline as the last one
## saw it and moves the camera so it fills the frame (the fill shrinks about as the distance
## grows).
func _aim(points: PackedVector3Array, direction: Vector3, up: Vector3, margin: float) -> void:
	var box: AABB = _box_of(points)
	var middle: Vector3 = box.get_center()
	var reach: float = box.size.length() / 2.0 / sin(deg_to_rad(FOV) / 2.0)
	for _pass: int in 3:
		_side_camera.position = middle + direction.normalized() * reach
		_side_camera.look_at(middle, up)
		var outline: Rect2 = _outline(points)
		var half: Vector2 = Vector2(_viewport.size) / 2.0
		middle = _side_camera.project_position(outline.get_center(), reach)
		var fill: Vector2 = outline.size / 2.0 / half
		reach *= maxf(fill.x, fill.y) * margin


## Where `points` lie on the side camera's frame, in pixels.
func _outline(points: PackedVector3Array) -> Rect2:
	var outline: Rect2 = Rect2(_side_camera.unproject_position(points[0]), Vector2.ZERO)
	for point: Vector3 in points:
		outline = outline.expand(_side_camera.unproject_position(point))
	return outline


## Whether a close-up hides `node`, a child of the main scene: everything but the game's light
## and ink outline (and the model and the camera), so the model stands on a bare background.
func _hidden_in_close_ups(node: Node) -> bool:
	return not (node == _piece or node == _side_camera or KEPT_IN_CLOSE_UPS.has(node.name))


## The bounds of every mesh under `model`, in the world.
func _bounds_of(model: Node3D) -> AABB:
	var bounds: AABB = AABB(model.global_position, Vector3.ZERO)
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		bounds = bounds.merge(mesh.global_transform * mesh.get_aabb())
	return bounds


## The box around `points`.
func _box_of(points: PackedVector3Array) -> AABB:
	var box: AABB = AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points:
		box = box.expand(point)
	return box


## Every vertex of every mesh under `model`, in the world, in the pose its skeleton holds now.
func _points_of(model: Node3D) -> PackedVector3Array:
	var points: PackedVector3Array = []
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var bones: Array[Transform3D] = _bones_of(mesh)
		for surface: int in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if not bones.is_empty() and arrays[Mesh.ARRAY_BONES] != null:
				vertices = _skinned(
					vertices,
					arrays[Mesh.ARRAY_BONES],
					arrays[Mesh.ARRAY_WEIGHTS],
					bones,
				)
			points.append_array(mesh.global_transform * vertices)
	return points


## Where each of `mesh`'s skin binds moves its vertices in the skeleton's current pose, or nothing
## when the mesh isn't skinned: what the renderer skins it by.
func _bones_of(mesh: MeshInstance3D) -> Array[Transform3D]:
	var skeleton: Skeleton3D = mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
	var bones: Array[Transform3D] = []
	if skeleton == null or mesh.skin == null:
		return bones
	for bind: int in mesh.skin.get_bind_count():
		var bone: int = mesh.skin.get_bind_bone(bind)
		if bone < 0:
			bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
		var pose: Transform3D = skeleton.get_bone_global_pose(bone) if bone >= 0 else Transform3D()
		bones.append(pose * mesh.skin.get_bind_pose(bind))
	return bones


## `vertices` skinned: each moved by its `weights` of its `binds`' `bones` (four or eight each).
func _skinned(
		vertices: PackedVector3Array,
		binds: PackedInt32Array,
		weights: PackedFloat32Array,
		bones: Array[Transform3D],
) -> PackedVector3Array:
	var per: int = 8 if binds.size() == vertices.size() * 8 else 4
	var skinned: PackedVector3Array = []
	var _sized: int = skinned.resize(vertices.size())
	for vertex: int in vertices.size():
		var point: Vector3 = Vector3.ZERO
		for slot: int in range(vertex * per, vertex * per + per):
			if weights[slot] > 0.0:
				point += bones[binds[slot]] * vertices[vertex] * weights[slot]
		skinned[vertex] = point
	return skinned


## Whether a point of `model` is in the face close-up: within FACE_SHARE of its height of the bone
## named "head" (in any case) of its skeleton, where its pose holds it now, or at the front and top
## of its bounds when it has none.
func _in_face(model: Node3D) -> Callable:
	var reach: float = _bounds.size.y * FACE_SHARE
	for node: Node in model.find_children("*", "Skeleton3D", true, false):
		var skeleton: Skeleton3D = node as Skeleton3D
		for bone: int in skeleton.get_bone_count():
			if skeleton.get_bone_name(bone).to_lower() == "head":
				var pose: Transform3D = skeleton.get_bone_global_pose(bone)
				var head: Vector3 = skeleton.global_transform * pose.origin
				return func(point: Vector3) -> bool: return point.distance_to(head) <= reach
	var front: Vector3 = _bounds.size * FACE_SHARE
	var face: AABB = AABB(_bounds.end - front, front)
	face.size.x = _bounds.size.x
	face.position.x = _bounds.position.x
	face = face.grow(0.001)
	return func(point: Vector3) -> bool: return face.has_point(point)


## The eight corners of `box`.
func _corners(box: AABB) -> PackedVector3Array:
	var corners: PackedVector3Array = []
	var _sized: int = corners.resize(8)
	for corner: int in 8:
		corners[corner] = box.get_endpoint(corner)
	return corners
