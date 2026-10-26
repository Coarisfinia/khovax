class_name MoveHint
extends Control
## The move hint (#1222): at the start of a new game, the glyphs that walk this machine's player
## stand just under them, for the device in use (InputGlyphs): the left stick, W, A, S and D, or a
## drag on touch (TouchStick). Once the player first walks it fades, and it never shows again for
## their profile (MoveHintKeeper). None while the game hears no input (the menu or a dialog is
## open), and none while the camera doesn't show the player.

## The walking actions, each with its place in the keys' block in glyph sides: W over S, with A
## and D beside it. A device whose actions all show one glyph (a stick, a drag) shows it once.
const CELLS: Dictionary[StringName, Vector2] = {
	&"move_up": Vector2(1.0, 0.0),
	&"move_left": Vector2(0.0, 1.0),
	&"move_down": Vector2(1.0, 1.0),
	&"move_right": Vector2(2.0, 1.0),
}
## The gap between the circle under the player and the hint, and between its glyphs, in pixels.
const GAP: float = 6.0
## How long the hint takes to fade once the player walks, in seconds.
const FADE_SECONDS: float = 0.6

@export var driver: Session
@export var camera: Camera3D
## The figure of this machine's player (PlayerView), which the hint stands under.
@export var figure: Node3D
@export var keeper: MoveHintKeeper

## Where each glyph shows now, by its action: empty while none shows. Tests read it.
var shown: Dictionary[StringName, Rect2] = {}
## The glyph each shows, by its action, taken with its place.
var glyphs: Dictionary[StringName, Texture2D] = {}
## How opaque the hint is: 1 until the player walks, then down to 0. Tests read it.
var alpha: float = 1.0


func _ready() -> void:
	# A profile that has walked before starts without the hint, rather than fading it in a game.
	if keeper == null or keeper.walked:
		alpha = 0.0


func _process(delta: float) -> void:
	fade(delta)
	show_state()


func _draw() -> void:
	for action: StringName in shown:
		ActionGlyph.draw_on(self, glyphs[action], shown[action], alpha)


## Fades the hint by `delta` seconds' worth once the player has walked; tests call it.
func fade(delta: float) -> void:
	if keeper != null and keeper.walked:
		alpha = maxf(alpha - delta / FADE_SECONDS, 0.0)


## Notes the player's first walk and places the glyphs under them, or hides them. Called every
## frame; tests call it.
func show_state() -> void:
	shown = {}
	glyphs = {}
	if keeper != null and not keeper.walked and _walks():
		keeper.walk()
	if alpha > 0.0 and _hears_input() and _figure_shown():
		_place_under(figure.global_position)
	queue_redraw()


## Whether this machine's player is walking now.
func _walks() -> bool:
	if driver == null or driver.state == null or driver.input == null:
		return false
	var player: Entity = driver.state.player(driver.input.slot)
	var movement: MovementFeature = driver.state.feature(MovementFeature.ID) as MovementFeature
	if player == null or movement == null:
		return false
	var walk: Walk = movement.walk(player.id)
	return walk != null and walk.is_moving()


## Whether the game hears this machine's player's input now: none while blocked or in a dialog.
func _hears_input() -> bool:
	if driver == null or driver.state == null or driver.input == null:
		return false
	return not driver.input.blocked and not driver.input.in_dialog


## Whether the camera shows the player's figure.
func _figure_shown() -> bool:
	if camera == null or figure == null or not figure.is_visible_in_tree():
		return false
	return camera.is_position_in_frustum(figure.global_position)


## Puts the glyphs, side by side as the keys lie, centred just under the circle around `feet`.
func _place_under(feet: Vector3) -> void:
	for action: StringName in CELLS:
		var glyph: Texture2D = InputGlyphs.of(action, DeviceInUse.device)
		if glyph != null and not glyphs.values().has(glyph):
			glyphs[action] = glyph
	if glyphs.is_empty():
		return
	var side: float = get_theme_default_font_size() * ActionGlyph.SIDE_FONTS
	var step: float = side + GAP
	var cells: Dictionary[StringName, Vector2] = {}
	var first: Vector2 = Vector2.INF
	var last: Vector2 = -Vector2.INF
	for action: StringName in glyphs:
		# One glyph for every action stands alone; keys keep their places in the block.
		cells[action] = Vector2.ZERO if glyphs.size() == 1 else CELLS[action]
		first = first.min(cells[action])
		last = last.max(cells[action])
	# Towards the camera along the ground is down on the screen.
	var toward: Vector3 = camera.global_basis.z * Vector3(1.0, 0.0, 1.0)
	var edge: Vector2 = camera.unproject_position(feet + toward.normalized() * PlayerCircle.RADIUS)
	var width: float = (last.x - first.x) * step + side
	var corner: Vector2 = Vector2(edge.x - width / 2.0, edge.y + GAP) - first * step
	for action: StringName in glyphs:
		shown[action] = Rect2(corner + cells[action] * step, Vector2(side, side))
