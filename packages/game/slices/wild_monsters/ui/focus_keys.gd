class_name FocusKeys
extends Control
## The focus keys' hint (#1210): while a keyboard or a controller is in use, the glyphs of
## focus_previous and focus_next (Q and R, or the shoulder buttons) stand left and right of the
## wild monster this machine's player focuses, beside its ring (FocusMark). While nothing is
## focused, they stand beside the nearest wild monster in reach, which a press focuses, so the
## player learns the keys before the first focus. None on touch, where a monster is tapped (#486),
## none while no wild monster in reach shows, and none while the game hears no input.

## The glyphs, from the left: the one that steps the focus back, and the one that steps it on.
const ACTIONS: Array[StringName] = [&"focus_previous", &"focus_next"]
## The gap between the ring's edge and a glyph, in pixels.
const GAP: float = 6.0

@export var driver: Session
@export var camera: Camera3D
@export var wild_view: WildMonsterView

## Where each glyph shows now, by its action: empty while none shows. Tests read it.
var shown: Dictionary[StringName, Rect2] = {}


func _process(_delta: float) -> void:
	show_state()


func _draw() -> void:
	for action: StringName in shown:
		ActionGlyph.draw_on(self, InputGlyphs.of(action, DeviceInUse.device), shown[action])


## Places the glyphs beside the wild monster the hint stands by, or hides them. Called every
## frame; tests call it.
func show_state() -> void:
	shown = {}
	var monster: int = hinted()
	if camera != null and wild_view != null and wild_view.figures.has(monster):
		var figure: HexPiece = wild_view.figures[monster]
		# Only a figure the camera shows: one just off the screen can project near its edge.
		if figure.is_visible_in_tree() and camera.is_position_in_frustum(figure.global_position):
			_place_beside(figure.global_position)
	queue_redraw()


## The wild monster the hint stands by: the focused one, else the nearest shown in reach, or
## Command.NO_FOCUS for none.
func hinted() -> int:
	if driver == null or driver.state == null or driver.input == null:
		return Command.NO_FOCUS
	if DeviceInUse.device == DeviceInUse.Device.TOUCH:
		return Command.NO_FOCUS
	if driver.input.blocked or driver.input.in_dialog:
		return Command.NO_FOCUS
	var state: GameState = driver.state
	var focus: int = driver.input.focus
	if WildMonsterView.is_shown(state, focus):
		return focus
	var player: Entity = state.player(driver.input.slot)
	if player == null:
		return Command.NO_FOCUS
	for monster: int in FocusChoice.nearest(state, player.tile):
		if WildMonsterView.is_shown(state, monster):
			return monster
	return Command.NO_FOCUS


## Puts each glyph just outside the ring around `feet`, on its side.
func _place_beside(feet: Vector3) -> void:
	var side: float = get_theme_default_font_size() * ActionGlyph.SIDE_FONTS
	for i: int in ACTIONS.size():
		var action: StringName = ACTIONS[i]
		if InputGlyphs.of(action, DeviceInUse.device) == null:
			continue
		var outward: float = -1.0 if i == 0 else 1.0
		var edge: Vector2 = camera.unproject_position(
			feet + Vector3(outward * FocusMark.RADIUS, 0.0, 0.0)
		)
		var left: float = edge.x + GAP if outward > 0.0 else edge.x - GAP - side
		shown[action] = Rect2(left, edge.y - side / 2.0, side, side)
