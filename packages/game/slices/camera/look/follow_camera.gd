@tool
class_name FollowCamera
extends Camera3D
## The game camera: looks down at a fixed, slightly tilted angle and never rotates. It follows a
## target on the ground plane, but only once the target leaves a dead zone around the camera's
## focus, and then with a capped speed and a low acceleration: no snapping, shaking or zooming,
## because the game is designed around motion sickness.
## A tool script, so the angle also shows in the editor. It only follows while the game runs, and
## processes after the views (process_priority in main.tscn), so it follows where they drew.

## The target to follow; the camera starts centered on it.
@export var target: Node3D
## Angle between the view direction and the ground: 90 is straight down.
@export_range(45.0, 90.0) var pitch_degrees: float = 65.0:
	set(value):
		pitch_degrees = value
		_place()
## Distance from the focus point on the ground to the camera.
@export var distance: float = 11.0:
	set(value):
		distance = value
		_place()
## The camera only moves once the target is further than this from its focus.
@export var dead_zone_radius: float = 2.0
## World units per second: just above walking speed (a tile every MovementFeature.MOVE_TICKS ticks),
## so the camera never falls behind a walking player for good (#726).
@export var max_speed: float = 6.5
## World units per second squared; low, so the camera eases in and out.
@export var acceleration: float = 1.5

## The point on the ground the camera looks at.
var focus: Vector3 = Vector3.ZERO
var _velocity: Vector3 = Vector3.ZERO
var _centered: bool = false


func _ready() -> void:
	if target != null:
		focus = _on_ground(target.global_position)
	_place()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# Centered on the target where the views first drew it, before anything is seen: when ready,
	# the target may not stand in place yet, e.g. a world resumed away from the origin (#119).
	if not _centered and target != null:
		_centered = true
		focus = _on_ground(target.global_position)
		_place()
		return
	advance(delta)


## Moves the focus by one time step. Called every frame; tests call it with fixed steps.
func advance(delta: float) -> void:
	if target == null:
		return
	var offset: Vector3 = _on_ground(target.global_position) - focus
	var desired: Vector3 = Vector3.ZERO
	var outside: float = offset.length() - dead_zone_radius
	if outside > 0.0:
		# Slows down as the target comes back inside the dead zone, so it eases in rather than
		# stopping at the edge.
		desired = offset.normalized() * minf(max_speed, outside)
	_velocity = _velocity.move_toward(desired, acceleration * delta)
	focus += _velocity * delta
	_place()


## The camera's world transform for the current focus: `focus` and the target are in world space,
## so the camera is placed in world space too, whatever its parent's transform.
func expected_transform() -> Transform3D:
	var pitch: float = deg_to_rad(pitch_degrees)
	var offset: Vector3 = Vector3(0.0, sin(pitch), cos(pitch)) * distance
	return Transform3D(Basis.from_euler(Vector3(-pitch, 0.0, 0.0)), focus + offset)


func _place() -> void:
	# Setters run while the scene loads, before the camera is in the tree; _ready places it again.
	if is_inside_tree():
		global_transform = expected_transform()


static func _on_ground(point: Vector3) -> Vector3:
	return Vector3(point.x, 0.0, point.z)
