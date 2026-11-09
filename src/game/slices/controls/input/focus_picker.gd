class_name FocusPicker
extends Node
## Focusing by tapping or clicking a wild monster (#486): a tap that lifts within TAP_SECONDS, near
## where it touched down, or a left click, focuses the wild monster whose figure shows nearest the
## point on the screen, within PICK_PIXELS. A tap still reaches the touch stick, but it lifts before
## it steers anywhere; a touch a button took doesn't pick. It sets the local input's focus, which
## the next command carries (#436), and, as any new tap, stops a walk to a tapped tile. A tap or
## click that focuses nothing walks the player to the tile under it instead (#1508,
## LocalInput.tap_tile); a touch's emulated click doesn't, or the start of a drag on the stick
## would walk too. A left click held past TAP_SECONDS, or moved past TAP_PIXELS, walks toward the
## cursor instead for as long as it's held (#1567, HeldWalk), and letting go stops there; touch
## keeps the stick for that.

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
## Whether a left click that walks is held (#1567), since `_held_seconds` ago, from `_pressed_at`.
var _pressing: bool = false
var _pressed_at: Vector2 = Vector2.ZERO
var _held_seconds: float = 0.0
## Whether the held click steers toward the cursor: it's no longer a click (_process).
var _steering: bool = false
## Where the mouse cursor is on the screen.
var _cursor: Vector2 = Vector2.ZERO


func _process(delta: float) -> void:
	if not _pressing:
		return
	# Held on over the menu or a dialog (#1509), it walks no more until it's pressed again.
	if not input.hears():
		_let_go()
		return
	_held_seconds += delta
	if _held_seconds > TAP_SECONDS:
		_steer()
	if not _steering:
		return
	var ground: Variant = _ground_under(_cursor)
	if ground is Vector3:
		var point: Vector3 = ground
		input.held_walk.hold(instance.to_local(point))
	else:
		input.held_walk.let_go()


# Every move and release, even one over the HUD, which takes them before _unhandled_input.
func _input(event: InputEvent) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		_cursor = motion.position
		# Latched at once: a click moved off and back, or let go before the next frame, isn't one.
		if _pressing and _cursor.distance_to(_pressed_at) > TAP_PIXELS:
			_steer()
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and not click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_let_go()


func _notification(what: int) -> void:
	# The release may never come once the window lost the focus.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_let_go()


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
			_pressing = true
			_pressed_at = click.position
			_cursor = click.position
			_held_seconds = 0.0


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
## meets the tiles' tops (#1508): with the camera tilted, a ray to the plane under them would cross
## into the next hex near a tile's edge.
func walk_to(point: Vector2) -> void:
	var ground: Variant = _ground_under(point)
	if ground is Vector3:
		var hit: Vector3 = ground
		input.tap_tile(HexLayout.to_tile(instance.to_local(hit)))
	else:
		# A tap off the ground (the sky) is a new tap all the same: it stops the walk.
		input.tap_walk.stop()


## Where the camera's ray through `point` on the screen meets the tiles' tops, in the world, or
## null when it misses them (the sky).
func _ground_under(point: Vector2) -> Variant:
	var tops: Plane = Plane(Vector3.UP, instance.global_position.y + HexGrid.TILE_HEIGHT)
	return tops.intersects_ray(camera.project_ray_origin(point), camera.project_ray_normal(point))


## Turns the held left click into a walk toward the cursor: it's no longer a click.
func _steer() -> void:
	if not _steering:
		_steering = true
		input.tap_walk.stop()


## Ends a held left click: a walk toward the cursor stops, a click's walk to its tile goes on.
func _let_go() -> void:
	_pressing = false
	_steering = false
	input.held_walk.let_go()


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
