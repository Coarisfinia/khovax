class_name WildHpBars
extends Control
## The wild monsters' HP bars (#814): a small bar by every wild monster that has lost HP, so a
## fight shows how much each one has left, which the damage numbers (#764) don't. One at full HP
## shows none, so a calm board stays clean, unless this machine's player focuses it (FocusMark,
## #436): the one their special will strike shows its bar, full. The bar's fill eases to the HP
## left rather than jumping, so each hit shows it dropping, and the HP left stands on it as a
## number, so it never relies on color (#68). It stands just below the ring around the monster's
## feet on the screen, on the camera's side: over its head it would cover the figure and the quest
## marker standing there (#300). A fainted wild monster shows none (its figure lies down), nor does
## one out of sight (fog, hiding: WildMonsterView.is_shown) or off the screen. It draws under the
## rest of the Hud (first in it, in main.tscn). It only reads the state and the local input.

## The bar's size, in the default font's sizes, and the number's on it.
const WIDTH_FONTS: float = 3.4
const HEIGHT_FONTS: float = 1.05
const NUMBER_FONTS: float = 0.85
## The gap between the ring's edge and the bar, in pixels.
const GAP: float = 2.0
## How fast the fill eases toward the HP left: the share of the way left it covers per second.
const EASE_RATE: float = 6.0
## How round the bar's corners are and how wide its ink border is, in pixels, as the UI's panels.
const CORNER: int = 4
const BORDER: int = 2
## The fill: the HP left, on the fog's color as the UI's panels are.
const FILL: Color = Color(0.85, 0.33, 0.3)

@export var driver: Session
@export var camera: Camera3D
@export var wild_view: WildMonsterView

## Where each bar shows now, by entity id: none while it doesn't. Tests read it.
var shown: Dictionary[int, Rect2] = {}
## The share of its full HP each wild monster's fill shows now, easing toward its HP left, by
## entity id. Kept for every figure, shown or not, so a first hit eases down from full.
var shares: Dictionary[int, float] = {}
## The HP left each wild monster's bar shows, by entity id.
var hps: Dictionary[int, int] = {}
var _backdrop: StyleBoxFlat
var _border: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop = _box(true)
	_border = _box(false)


func _process(delta: float) -> void:
	show_state(delta)


func _draw() -> void:
	var font: Font = get_theme_default_font()
	var size_px: int = int(get_theme_default_font_size() * NUMBER_FONTS)
	for entity_id: int in shown:
		var bar: Rect2 = shown[entity_id]
		draw_style_box(_backdrop, bar)
		var inner: Rect2 = bar.grow(-BORDER)
		inner.size.x *= shares[entity_id]
		if inner.size.x > 0.0:
			draw_rect(inner, FILL)
		draw_style_box(_border, bar)
		var text: String = str(hps[entity_id])
		var wide: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px)
		var baseline: float = (
			bar.get_center().y + (font.get_ascent(size_px) - font.get_descent(size_px)) / 2.0
		)
		var at: Vector2 = Vector2(bar.get_center().x - wide.x / 2.0, baseline)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Toon.INK)


## Eases every fill `delta` seconds on toward its HP left and places the bars that show. Called
## every frame; tests call it, with 0 to place them without easing.
func show_state(delta: float = 0.0) -> void:
	shown = {}
	if driver == null or driver.state == null or wild_view == null or camera == null:
		queue_redraw()
		return
	var state: GameState = driver.state
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	for entity_id: int in shares.keys():
		if not wild_view.figures.has(entity_id):
			var _dropped: bool = shares.erase(entity_id)
			_dropped = hps.erase(entity_id)
	if health == null or wild == null:
		queue_redraw()
		return
	var focus: int = driver.input.focus if driver.input != null else Command.NO_FOCUS
	for entity_id: int in wild_view.figures:
		if state.entity(entity_id) == null:
			continue
		var full: int = health.max_hp_of(state, entity_id)
		var hp: int = health.hp_of(state, entity_id)
		var share: float = clampf(float(hp) / float(maxi(full, 1)), 0.0, 1.0)
		var eased: float = shares.get(entity_id, share)
		shares[entity_id] = lerpf(eased, share, 1.0 - exp(-EASE_RATE * delta))
		hps[entity_id] = hp
		if (hp < full or entity_id == focus) and not wild.is_fainted(entity_id):
			_place(entity_id)
	queue_redraw()


## Places the bar of the wild monster `entity_id` below its figure's ring, if the camera shows it.
func _place(entity_id: int) -> void:
	var figure: HexPiece = wild_view.figures[entity_id]
	if not figure.is_visible_in_tree() or not WildMonsterView.is_shown(driver.state, entity_id):
		return
	# Only a figure the camera shows: one just off the screen can project near its edge.
	if not camera.is_position_in_frustum(figure.global_position):
		return
	var fonts: float = get_theme_default_font_size()
	var bar: Vector2 = Vector2(WIDTH_FONTS, HEIGHT_FONTS) * fonts
	var front: Vector3 = figure.global_position + Vector3(0.0, 0.0, FocusMark.RADIUS)
	var edge: Vector2 = camera.unproject_position(front)
	shown[entity_id] = Rect2(edge.x - bar.x / 2.0, edge.y + GAP, bar.x, bar.y)


## The bar's backdrop (`filled`: the fog, as the UI's panels) or its ink border, rounded.
static func _box(filled: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.draw_center = filled
	style.bg_color = FogView.FOG
	style.border_color = Toon.INK
	style.set_border_width_all(0 if filled else BORDER)
	style.set_corner_radius_all(CORNER)
	return style
