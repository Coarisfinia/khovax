class_name FocusKeys
extends Control
## The focus keys' hint (#1210): while a keyboard or a controller is in use, the glyphs of
## focus_previous and focus_next (Q and R, or the shoulder buttons) stand left and right of the
## wild monster this machine's player focuses, beside its ring (FocusMark). While nothing is
## focused, they stand beside the nearest wild monster in reach, which a press focuses, so the
## player learns the keys before the first focus. None on touch, where a monster is tapped (#486),
## none while no wild monster in reach shows, and none while the game hears no input.
## With the mouse or touch, the glyph of a click or a tap (InputGlyphs.POINTING, #1248) stands just
## under where the ring would show on the nearest wild monster in reach that isn't focused, which a
## click or tap on it focuses (FocusPicker); none with a controller, which can't point.

## The glyphs, from the left: the one that steps the focus back, and the one that steps it on.
const ACTIONS: Array[StringName] = [&"focus_previous", &"focus_next"]
## Where the click's or tap's glyph shows in `shown` and `glyphs`: no InputMap action presses it.
const POINTING: StringName = &"pointing"
## The gap between the ring's edge and a glyph, in pixels.
const GAP: float = 6.0

@export var driver: Session
@export var camera: Camera3D
@export var wild_view: WildMonsterView

## Where each glyph shows now, by its action (or POINTING): empty while none shows. Tests read it.
var shown: Dictionary[StringName, Rect2] = {}
## The glyph each shows, by its action, taken with its place: the device in use can change before
## the next draw.
var glyphs: Dictionary[StringName, Texture2D] = {}


func _process(_delta: float) -> void:
	show_state()


func _draw() -> void:
	for action: StringName in shown:
		ActionGlyph.draw_on(self, glyphs[action], shown[action])


## Places the glyphs beside the wild monsters the hints stand by, or hides them. Called every
## frame; tests call it.
func show_state() -> void:
	shown = {}
	glyphs = {}
	var hinted_figure: HexPiece = _figure_shown(hinted())
	if hinted_figure != null:
		_place_beside(hinted_figure.global_position)
	var pointed_figure: HexPiece = _figure_shown(pointed())
	if pointed_figure != null:
		_place_under(pointed_figure.global_position)
	queue_redraw()


## The wild monster the keys' hint stands by: the focused one, else the nearest shown in reach, or
## Command.NO_FOCUS for none.
func hinted() -> int:
	if DeviceInUse.device == DeviceInUse.Device.TOUCH or not _hears_input():
		return Command.NO_FOCUS
	var focus: int = driver.input.focus
	if WildMonsterView.is_shown(driver.state, focus):
		return focus
	return _nearest_shown(Command.NO_FOCUS)


## The wild monster the click's or tap's glyph stands by: the nearest shown in reach but the focused
## one, or Command.NO_FOCUS for none and with a controller.
func pointed() -> int:
	if InputGlyphs.pointing(DeviceInUse.device) == null or not _hears_input():
		return Command.NO_FOCUS
	return _nearest_shown(driver.input.focus)


## Whether the game hears this machine's player's input now: none while blocked or in a dialog.
func _hears_input() -> bool:
	if driver == null or driver.state == null or driver.input == null:
		return false
	return not driver.input.blocked and not driver.input.in_dialog


## The nearest wild monster in reach of this machine's player that shows, but `skipped`, or
## Command.NO_FOCUS for none.
func _nearest_shown(skipped: int) -> int:
	var state: GameState = driver.state
	var player: Entity = state.player(driver.input.slot)
	if player == null:
		return Command.NO_FOCUS
	for monster: int in FocusChoice.nearest(state, player.tile):
		if monster != skipped and WildMonsterView.is_shown(state, monster):
			return monster
	return Command.NO_FOCUS


## The figure of `monster` while the camera shows it, else null.
func _figure_shown(monster: int) -> HexPiece:
	if camera == null or wild_view == null or not wild_view.figures.has(monster):
		return null
	var figure: HexPiece = wild_view.figures[monster]
	# Only a figure the camera shows: one just off the screen can project near its edge.
	if not figure.is_visible_in_tree() or not camera.is_position_in_frustum(figure.global_position):
		return null
	return figure


## Puts each glyph just outside the ring around `feet`, on its side.
func _place_beside(feet: Vector3) -> void:
	var side: float = get_theme_default_font_size() * ActionGlyph.SIDE_FONTS
	for i: int in ACTIONS.size():
		var action: StringName = ACTIONS[i]
		var glyph: Texture2D = InputGlyphs.of(action, DeviceInUse.device)
		if glyph == null:
			continue
		var outward: float = -1.0 if i == 0 else 1.0
		var edge: Vector2 = camera.unproject_position(
			feet + Vector3(outward * FocusMark.RADIUS, 0.0, 0.0)
		)
		var left: float = edge.x + GAP if outward > 0.0 else edge.x - GAP - side
		shown[action] = Rect2(left, edge.y - side / 2.0, side, side)
		glyphs[action] = glyph


## Puts the click's or tap's glyph just under the ring's place around `feet` on the screen.
func _place_under(feet: Vector3) -> void:
	var side: float = get_theme_default_font_size() * ActionGlyph.SIDE_FONTS
	# Towards the camera along the ground is down on the screen.
	var toward: Vector3 = camera.global_basis.z * Vector3(1.0, 0.0, 1.0)
	var edge: Vector2 = camera.unproject_position(feet + toward.normalized() * FocusMark.RADIUS)
	shown[POINTING] = Rect2(edge.x - side / 2.0, edge.y + GAP, side, side)
	glyphs[POINTING] = InputGlyphs.pointing(DeviceInUse.device)
