# gdstyle:ignore-file=quality/no-debug-print
# The tool reports what it wrote on stdout; that is what it is for.
extends SceneTree
## Renders a model inside the real game (the model skill's in-game check, #990): the main scene
## runs in a SubViewport, under the game's cel shading, ink outline and sun, and the model stands
## on the tile beside the player, idling. It writes the model from six sides (front, back, left,
## right, top, three-quarter) and the shot from the game camera at play distance; or, given a
## clip, that clip's frames for a GIF, from the game camera or from one of the six sides.
##
## Render it hidden and silent, as AGENTS.md's screenshot recipe says (the temporary one-pixel
## `override.cfg`, `--audio-driver Dummy`, and `--display-driver wayland` under WSLg):
##   godot --path . --audio-driver Dummy -s res://tools/models/render_in_game.gd -- \
##     res://assets/<name>/<name>.glb <out_dir> [size=1280x720] [clip=<Clip> [from=<view>]] \
##     --seed=0 --user-dir=<branch>
## The launch options after it (LaunchOptions) start the world as the game would.

## Frames the game draws before the first capture: shaders compile and the fog eases open.
const SETTLE_FRAMES: int = 90
## How far the side cameras stand from the model's middle, and how high that middle is.
const VIEW_DISTANCE: float = 3.2
const MIDDLE_HEIGHT: float = 0.6
## Where each side camera stands, seen from the model, which faces +Z like every model in the game.
const VIEWS: Dictionary[String, Vector3] = {
	"front": Vector3(0.0, 0.25, 1.0),
	"back": Vector3(0.0, 0.25, -1.0),
	"left": Vector3(1.0, 0.25, 0.0),
	"right": Vector3(-1.0, 0.25, 0.0),
	"top": Vector3(0.0, 1.0, 0.01),
	"three_quarter": Vector3(0.8, 0.7, 0.8),
}
## What the side shots hide, under the main scene: the HUD and the trees and rocks, which would
## stand between the camera and the model.
const HIDDEN_IN_SIDES: Array[String] = ["Hud", "Instance/TileDecorations"]
## How many tiles from the player the model stands for the side shots, so the player isn't in the
## way either; for the game shot it stands right beside them.
const SIDES_AWAY: int = 3
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
var _animations: AnimationPlayer
var _side_camera: Camera3D
var _game_camera: Camera3D


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
	_piece.tile = _beside(driver.state, driver.state.player(0).tile, 1)
	_animations = model.find_child("AnimationPlayer") as AnimationPlayer
	_game_camera = _main.get_node("Camera3D") as Camera3D
	_side_camera = Camera3D.new()
	_side_camera.fov = 40.0
	_main.add_child(_side_camera)
	if _clip.is_empty():
		_animations.play(&"Idle")
		_add_shot("game", _game_camera.make_current)
		for side: String in VIEWS:
			_add_shot(side, _pose_side.bind(side, driver.state))
		return
	if VIEWS.has(_from):
		_pose_side(_from, driver.state)
	else:
		_game_camera.make_current()
	_animations.play(StringName(_clip))
	_animations.pause()
	var length: float = _animations.get_animation(StringName(_clip)).length
	for frame: int in ceili(length * CLIP_FPS) + 1:
		_add_shot(
			"%s_%03d" % [_clip, frame],
			_animations.seek.bind(minf(frame / CLIP_FPS, length), true),
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


## A tile `steps` from `tile` in a straight line that the region has, so the model stands on
## ground near the player.
func _beside(state: GameState, tile: Vector2i, steps: int) -> Vector2i:
	for direction: Vector2i in Hex.DIRECTIONS:
		if state.region.has_tile(tile + direction * steps):
			return tile + direction * steps
	return tile


## Looks at the model's middle from `side` (VIEWS), away from the player and its decorations.
func _pose_side(side: String, state: GameState) -> void:
	_piece.tile = _beside(state, state.player(0).tile, SIDES_AWAY)
	var middle: Vector3 = _piece.global_position + Vector3.UP * MIDDLE_HEIGHT
	for path: String in HIDDEN_IN_SIDES:
		var hidden: Node = _main.get_node(path)
		hidden.set("visible", false)
	_side_camera.make_current()
	_side_camera.position = middle + VIEWS[side].normalized() * VIEW_DISTANCE
	_side_camera.look_at(middle, Vector3.FORWARD if side == "top" else Vector3.UP)
