extends RefCounted
## Camera flow: the camera looks down at the cube from a fixed 65 degree angle, stays put while the
## cube moves inside its dead zone, and follows smoothly once the cube leaves it, without jumps,
## sudden speed changes or any rotation, also under a moved and turned parent. Time is stepped by
## hand, so the flow is deterministic; one last step lets the engine's own frames drive it.

const STEP: float = 1.0 / 60.0
## The decided camera angle (#8): mostly top-down with a slight tilt.
const PITCH_DEGREES: float = 65.0
## Tolerance for float comparisons of positions accumulated over many steps.
const EPSILON: float = 0.0001

var _main: Node3D
var _camera: FollowCamera
var _cube: HexPiece
var _start_basis: Basis


func run(tree: SceneTree) -> String:
	var path: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return "main scene failed to load"
	_main = scene.instantiate() as Node3D
	tree.root.add_child(_main)
	await tree.process_frame
	_camera = _main.get_viewport().get_camera_3d() as FollowCamera
	_cube = _main.get_node_or_null("Cube") as HexPiece
	if _camera == null or _cube == null:
		_main.queue_free()
		return "the main scene needs a FollowCamera as its active camera and a HexPiece Cube"
	# Stepped by hand until the last step.
	_camera.set_process(false)
	_start_basis = _camera.global_basis

	var steps: Array[Callable] = [
		_check_angle,
		_check_starts_on_target,
		_check_dead_zone,
		_check_follows_smoothly,
		_check_under_moved_parent,
	]
	var result: String = ""
	for step: Callable in steps:
		result = step.call()
		if not result.is_empty():
			break
	if result.is_empty():
		result = await _check_runs_by_itself(tree)
	_main.queue_free()
	await tree.process_frame
	return result


func _check_angle() -> String:
	if not is_equal_approx(_camera.pitch_degrees, PITCH_DEGREES):
		return "the pitch is %f degrees, not %f" % [_camera.pitch_degrees, PITCH_DEGREES]
	var expected: Basis = Basis.from_euler(Vector3(-deg_to_rad(PITCH_DEGREES), 0.0, 0.0))
	if not _camera.global_basis.is_equal_approx(expected):
		return "the camera's orientation is not a pure %f degree pitch" % PITCH_DEGREES
	return ""


func _check_starts_on_target() -> String:
	if not _camera.focus.is_equal_approx(_ground(_cube.global_position)):
		return "the camera doesn't start centered on the cube"
	return _check_placed()


## A neighboring tile is closer than the dead zone's radius: the camera must not move at all.
func _check_dead_zone() -> String:
	_cube.tile += Vector2i(1, 0)
	var before: Vector3 = _camera.global_position
	_advance(120)
	if not _camera.global_position.is_equal_approx(before):
		return "the camera moved while the cube was inside the dead zone"
	return ""


## A tile far away: the camera follows with capped speed and acceleration, stays placed at its
## focus with the fixed angle on every step, and ends with the cube back inside the dead zone.
func _check_follows_smoothly() -> String:
	_cube.tile = Vector2i(-3, 3)
	var previous_speed: float = 0.0
	for _i: int in 1200:
		var before: Vector3 = _camera.global_position
		_advance(1)
		var speed: float = before.distance_to(_camera.global_position) / STEP
		if speed > _camera.max_speed + EPSILON:
			return "the camera moved at %f units/s, above its cap" % speed
		if absf(speed - previous_speed) > _camera.acceleration * STEP + EPSILON:
			return "the camera's speed jumped from %f to %f units/s" % [previous_speed, speed]
		previous_speed = speed
		var placed: String = _check_placed()
		if not placed.is_empty():
			return placed
	var left: float = _camera.focus.distance_to(_ground(_cube.global_position))
	if left > _camera.dead_zone_radius + EPSILON:
		return "after 20 s the cube is still %f from the camera's focus" % left
	return ""


## The camera works in world space: a moved and turned parent must neither shift it twice nor turn
## its view.
func _check_under_moved_parent() -> String:
	_main.position = Vector3(5.0, 0.0, -3.0)
	_main.rotation = Vector3(0.0, deg_to_rad(30.0), 0.0)
	_advance(600)
	var placed: String = _check_placed()
	if not placed.is_empty():
		return "under a moved parent: " + placed
	var left: float = _camera.focus.distance_to(_ground(_cube.global_position))
	if left > _camera.dead_zone_radius + EPSILON:
		return "under a moved parent the cube is %f from the camera's focus" % left
	return ""


## The engine's own frames drive the camera through _process, and it stays placed.
func _check_runs_by_itself(tree: SceneTree) -> String:
	_camera.set_process(true)
	# A few frames' worth of time, so _process runs several times.
	await tree.create_timer(0.2).timeout
	return _check_placed()


func _check_placed() -> String:
	if not _camera.global_transform.is_equal_approx(_camera.expected_transform()):
		return "the camera is not at its focus offset"
	if not _camera.global_basis.is_equal_approx(_start_basis):
		return "the camera turned"
	return ""


func _advance(steps: int) -> void:
	for _i: int in steps:
		_camera.advance(STEP)


func _ground(point: Vector3) -> Vector3:
	return Vector3(point.x, 0.0, point.z)
