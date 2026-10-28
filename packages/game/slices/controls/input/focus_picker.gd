class_name FocusPicker
extends Node
## Focusing by tapping or clicking a wild monster (#486): a tap that lifts within TAP_SECONDS, near
## where it touched down, or a left click, focuses the wild monster whose figure shows nearest the
## point on the screen, within PICK_PIXELS. A tap still reaches the touch stick, but it lifts before
## it steers anywhere; a touch a button took doesn't pick. It sets the local input's focus, which
## the next command carries (#436), and, as any new tap, stops a walk to a tapped tile. A tap or
## click that focuses nothing walks the player to the tile under it instead (#1508,
## LocalInput.tap_tile); a touch's emulated click doesn't, or the start of
## a
## drag on the stick would walk too.

## How quick and how still a touch has to be to count as a tap.
const TAP_SECONDS: float = 0.3
const TAP_PIXELS: float = 16.0
## How near a wild monster's figure has to show to the tap or click, on the screen.
const PICK_PIXELS: float = 80.0

@export var input: LocalInput
@export var camera: Camera3D
@export var wild_view: WildMonsterView
## The local instance's views, shifted to its place in the world (InstanceRoot): a tapped point is
## turned back into the instance's own coordinates through it.
@export var instance: Node3D

## Where and when each finger touched down, by touch index.
var _downs: Dictionary[int, Vector3] = {}


func _unhandled_input(event: InputEvent) -> void:
	# No tap or click reaches the world while the menu or a dialog is open (#1509).
	if not input.hears():
		return
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		_on_touch(touch)
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		if pick(click.position):
			# A touch's emulated click comes at touch-down, before it's known to be a tap.
			if click.device != InputEvent.DEVICE_ID_EMULATION:
				input.tap_walk.stop()
		elif click.device != InputEvent.DEVICE_ID_EMULATION:
			walk_to(click.position)


## Focuses the wild monster whose figure shows nearest `point` on the screen, within PICK_PIXELS;
## returns whether one was focused.
func pick(point: Vector2) -> bool:
	var best: int = Command.NO_FOCUS
	var nearest: float = PICK_PIXELS
	for monster: int in wild_view.figures:
		var figure: HexPiece = wild_view.figures[monster]
		# Only a figure the camera shows: one just off the screen can project near its edge.
		if (not figure.is_visible_in_tree()
				or not camera.is_position_in_frustum(figure.global_position)):
			continue
		var shown: float = camera.unproject_position(figure.global_position).distance_to(point)
		if shown < nearest:
			nearest = shown
			best = monster
	if best != Command.NO_FOCUS:
		input.focus = best
	return best != Command.NO_FOCUS


## Walks the player to the tile shown at `point` on the screen, where the camera's ray through it
## meets the ground (#1508).
func walk_to(point: Vector2) -> void:
	var ground: Variant = Plane(Vector3.UP).intersects_ray(
		camera.project_ray_origin(point),
		camera.project_ray_normal(point),
	)
	if ground is Vector3:
		var hit: Vector3 = ground
		input.tap_tile(HexLayout.to_tile(instance.to_local(hit)))


func _on_touch(touch: InputEventScreenTouch) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if touch.pressed:
		_downs[touch.index] = Vector3(touch.position.x, touch.position.y, now)
		return
	if not _downs.has(touch.index):
		return
	var down: Vector3 = _downs[touch.index]
	var _dropped: bool = _downs.erase(touch.index)
	var still: bool = Vector2(down.x, down.y).distance_to(touch.position) <= TAP_PIXELS
	if touch.canceled or not still or now - down.z > TAP_SECONDS:
		return
	if pick(touch.position):
		input.tap_walk.stop()
	else:
		walk_to(touch.position)
