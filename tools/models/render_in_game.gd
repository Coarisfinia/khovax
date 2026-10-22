# gdstyle:ignore-file=quality/no-debug-print
# The tool reports what it wrote on stdout; that is what it is for.
extends SceneTree
## Renders a model inside the real game (the model skill's in-game check, #990): the main scene
## runs in a SubViewport, under the game's cel shading, ink outline and sun, and the model stands
## on the tile beside the player, idling. It writes the model from six sides (front, back, left,
## right, top, three-quarter), the shot from the game camera at play distance, and two close-ups
## on a bare background as its codex page shows it full-screen (#995): the whole model
## ("portrait") and its front end, the face ("face"). Given a clip, it writes that clip's frames
## for a GIF instead, from the game camera or from any of those views. Any model works: the
## cameras frame it by its bounds. With `points`, it marks the model's attachment points
## (PointMarks, #1007).
##
## Render it off the desktop and silent, as AGENTS.md's screenshot recipe says:
##   uv run --locked tools/godot/offscreen.py -- --path . \
##     -s res://tools/models/render_in_game.gd -- \
##     res://assets/<name>/<name>.glb <out_dir> [size=1280x720] [clip=<Clip> [from=<view>]] \
##     [points] \
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
## The face close-up frames this share of the model's length at its front end, and of its height
## at the top.
const FACE_SHARE: float = 0.4
## What the side shots keep of the instance: only the ground. The HUD, the player, the people,
## the other monsters and the trees would stand between the camera and the model.
const KEPT_IN_SIDES: String = "HexGrid"
## How much a clip's framing grows the resting bounds, as a share of their size.
const CLIP_ROOM: float = 0.1
## A clip's frames are captured this many times a second of the clip.
const CLIP_FPS: float = 15.0
## Frames to wait after posing a shot before capturing it, so the pose has been drawn.
const DRAW_FRAMES: int = 2

var _viewport: SubViewport
var _main: Node3D
var _out_dir: String = ""
var _model_path: String = ""
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
		_model_path = args[0]
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
	_viewport.add_child(_main)


## Stands the model on the tile beside the player and lists the shots.
func _place() -> void:
	var driver: GameDriver = _main.get_node("Driver") as GameDriver
	_piece = HexPiece.new()
	_piece.base_offset = 0.0
	var model: Node3D = (load(_model_path) as PackedScene).instantiate() as Node3D
	Toon.apply_to_model(model)
	_piece.add_child(model)
	_main.add_child(_piece)
	_piece.tile = _beside(driver.state, driver.state.player(0).tile)
	var animations: AnimationPlayer = model.find_child("AnimationPlayer") as AnimationPlayer
	_game_camera = _main.get_node("Camera3D") as Camera3D
	_side_camera = Camera3D.new()
	_main.add_child(_side_camera)
	_side_camera.fov = FOV
	_bounds = _bounds_of(model)
	if OS.get_cmdline_user_args().has("points"):
		_piece.add_child(PointMarks.new(model, _bounds.size.y))
	if not _clip.is_empty():
		# The bounds are the resting pose's: room for a clip to lunge or stretch out of them.
		_bounds = _bounds.grow(_bounds.size.length() * CLIP_ROOM)
	if _clip.is_empty():
		animations.play(&"Idle")
		_add_shot("game", _game_camera.make_current)
		for side: String in VIEWS:
			_add_shot(side, _pose_side.bind(side))
		return
	if VIEWS.has(_from):
		_pose_side(_from)
	else:
		_game_camera.make_current()
	animations.play(StringName(_clip))
	animations.pause()
	var length: float = animations.get_animation(StringName(_clip)).length
	for frame: int in ceili(length * CLIP_FPS) + 1:
		_add_shot(
			"%s_%03d" % [_clip, frame],
			animations.seek.bind(minf(frame / CLIP_FPS, length), true),
		)


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
	var hidden: Array[Node] = _main.get_node("Instance").get_children()
	if CLOSE_UPS.has(side):
		hidden = _main.get_children().filter(_hidden_in_close_ups)
	hidden.append(_main.get_node("Hud"))
	for node: Node in hidden:
		var kept: bool = node.name == KEPT_IN_SIDES and not CLOSE_UPS.has(side)
		# Stopped too, so a view that shows its node each frame doesn't show it again.
		node.process_mode = Node.PROCESS_MODE_INHERIT if kept else Node.PROCESS_MODE_DISABLED
		node.set("visible", kept)
	var framed: AABB = _bounds
	if side == "face":
		var front: Vector3 = Vector3(_bounds.size.x, _bounds.size.y, _bounds.size.z) * FACE_SHARE
		framed = AABB(_bounds.end - front, front)
		framed.size.x = _bounds.size.x
		framed.position.x = _bounds.position.x
	var middle: Vector3 = framed.get_center()
	var reach: float = framed.size.length() / 2.0 / sin(deg_to_rad(FOV) / 2.0)
	_side_camera.make_current()
	# Twice: place the camera, see how much of the frame the bounds fill, and move it so they fill
	# it but for the margin (the fill shrinks about as the distance grows).
	for _pass: int in 2:
		_side_camera.position = middle + VIEWS[side].normalized() * reach
		_side_camera.look_at(middle, Vector3.FORWARD if side == "top" else Vector3.UP)
		reach *= _fill(framed) * MARGIN


## Whether a close-up hides `node`, a child of the main scene: everything but the game's light
## and ink outline (and the model and the camera), so the model stands on a bare background.
func _hidden_in_close_ups(node: Node) -> bool:
	return not (node == _piece or node == _side_camera or KEPT_IN_CLOSE_UPS.has(node.name))


## How much of the frame `box` fills seen from the side camera: 1 when it just touches an edge.
func _fill(box: AABB) -> float:
	var half: Vector2 = Vector2(_viewport.size) / 2.0
	var fill: float = 0.0
	for corner: int in 8:
		var spot: Vector2 = _side_camera.unproject_position(box.get_endpoint(corner)) - half
		fill = maxf(fill, maxf(absf(spot.x) / half.x, absf(spot.y) / half.y))
	return fill


## The bounds of every mesh under `model`, in the world.
func _bounds_of(model: Node3D) -> AABB:
	var bounds: AABB = AABB(model.global_position, Vector3.ZERO)
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		bounds = bounds.merge(mesh.global_transform * mesh.get_aabb())
	return bounds
