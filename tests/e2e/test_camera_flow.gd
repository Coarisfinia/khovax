extends RefCounted
## Camera flow: the camera looks down at the cube from a fixed, slightly tilted angle, stays put
## while the cube moves inside its dead zone, and follows smoothly once the cube leaves it, without
## jumps, sudden speed changes or any rotation. Time is stepped by hand, so the flow is
## deterministic.

const STEP: float = 1.0 / 60.0
## Tolerance for float comparisons of positions accumulated over many steps.
const EPSILON: float = 0.0001

var _main: Node
var _camera: FollowCamera
var _cube: HexPiece
var _start_rotation: Vector3


func run(tree: SceneTree) -> String:
	var path: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return "main scene failed to load"
	_main = scene.instantiate()
	tree.root.add_child(_main)
	await tree.process_frame
	_camera = _main.get_viewport().get_camera_3d() as FollowCamera
	_cube = _main.get_node_or_null("Cube") as HexPiece
	if _camera == null or _cube == null:
		_main.queue_free()
		return "the main scene needs a FollowCamera as its active camera and a HexPiece Cube"
	# Stepped by hand from here on.
	_camera.set_process(false)
	_start_rotation = _camera.rotation

	var steps: Array[Callable] = [
		_check_angle,
		_check_starts_on_target,
		_check_dead_zone,
		_check_follows_smoothly,
		_check_never_rotates,
	]
	var result: String = ""
	for step: Callable in steps:
		result = step.call()
		if not result.is_empty():
			break
	_main.queue_free()
	await tree.process_frame
	return result


func _check_angle() -> String:
	if _camera.pitch_degrees < 55.0 or _camera.pitch_degrees >= 90.0:
		return "pitch %f is not mostly top-down with a slight tilt" % _camera.pitch_degrees
	var expected: Vector3 = Vector3(-deg_to_rad(_camera.pitch_degrees), 0.0, 0.0)
	if not _camera.rotation.is_equal_approx(expected):
		return "the camera's rotation %s is not the configured pitch" % _camera.rotation
	return ""


func _check_starts_on_target() -> String:
	if not _camera.focus.is_equal_approx(_ground(_cube.global_position)):
		return "the camera doesn't start centered on the cube"
	return ""


## A neighboring tile is closer than the dead zone's radius: the camera must not move at all.
func _check_dead_zone() -> String:
	_cube.tile += Vector2i(1, 0)
	var before: Vector3 = _camera.global_position
	_advance(120)
	if not _camera.global_position.is_equal_approx(before):
		return "the camera moved while the cube was inside the dead zone"
	return ""


## A tile far away: the camera follows with capped speed and acceleration, and ends with the cube
## back inside the dead zone.
func _check_follows_smoothly() -> String:
	_cube.tile = Vector2i(-3, 3)
	var previous_speed: float = 0.0
	for _i: int in 1200:
		var before: Vector3 = _camera.focus
		_advance(1)
		var speed: float = before.distance_to(_camera.focus) / STEP
		if speed > _camera.max_speed + EPSILON:
			return "the camera moved at %f units/s, above its cap" % speed
		if absf(speed - previous_speed) > _camera.acceleration * STEP + EPSILON:
			return "the camera's speed jumped from %f to %f units/s" % [previous_speed, speed]
		previous_speed = speed
	var left: float = _camera.focus.distance_to(_ground(_cube.global_position))
	if left > _camera.dead_zone_radius + EPSILON:
		return "after 20 s the cube is still %f from the camera's focus" % left
	return ""


func _check_never_rotates() -> String:
	if not _camera.rotation.is_equal_approx(_start_rotation):
		return "the camera rotated"
	return ""


func _advance(steps: int) -> void:
	for _i: int in steps:
		_camera.advance(STEP)


func _ground(point: Vector3) -> Vector3:
	return Vector3(point.x, 0.0, point.z)
