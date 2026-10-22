class_name ActionGlyph
extends Control
## A hint on a button (#583): the glyph of the key or controller button that presses it, for the
## device in use (DeviceInUse): inside a button with words, at its right end, and over an icon
## button's bottom right corner. It shows none for touch, where
## the button itself is tapped, and none while the button is hidden or rests; with `only_focused`,
## only while the button has the focus, which is what the confirming key or button presses. It
## follows a change of device at once.

## The glyph's side, in the button's font sizes.
const SIDE_FONTS: float = 2.2
## How far the glyph stands out over an icon button's corner, as a share of its side.
const OVERHANG: float = 0.5
## How far in from a button with words' right end it lies, as a share of its side.
const INSIDE: float = 0.15
## Its side at most there, as a share of the button's height.
const INSIDE_HEIGHT: float = 0.9
## How far in from the glyph's edges its backdrop lies, as a share of its side: a rounded fog tile
## under the glyph's shape, so its open parts (the letters cut out of a key) show the fog, not what
## lies behind.
const BACKDROP_INSET: float = 0.14
const CORNER: int = 6

## The InputMap action whose key or button the glyph shows.
var action: StringName = &""
## Whether it shows only while its button has the focus.
var only_focused: bool = false
## The glyph shown now, or null while none shows.
var texture: Texture2D
var _backdrop: StyleBoxFlat = _make_backdrop()


func _process(_delta: float) -> void:
	follow()


func _draw() -> void:
	if texture == null:
		return
	var area: Rect2 = Rect2(Vector2.ZERO, size)
	draw_style_box(_backdrop, area.grow(-size.x * BACKDROP_INSET))
	draw_texture_rect(texture, area, false, Toon.INK)


## Puts a glyph for `pressed_by` on `button`'s corner.
static func badge(button: Button, pressed_by: StringName, focused: bool = false) -> ActionGlyph:
	var glyph: ActionGlyph = ActionGlyph.new()
	glyph.action = pressed_by
	glyph.only_focused = focused
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(glyph)
	return glyph


## Shows the glyph the device in use has now, where its button is now; tests call it.
func follow() -> void:
	var button: Button = get_parent() as Button
	var shown: Texture2D = null
	if button != null and button.is_visible_in_tree() and not button.disabled:
		if not only_focused or button.has_focus():
			shown = InputGlyphs.of(action, DeviceInUse.device)
	if shown != texture:
		texture = shown
		queue_redraw()
	if button == null:
		return
	var side: float = button.get_theme_default_font_size() * SIDE_FONTS
	if button.size.x > button.size.y * 2.0:
		# A button with words: at its right end, inside it.
		side = minf(side, button.size.y * INSIDE_HEIGHT)
		size = Vector2(side, side)
		position = Vector2(button.size.x - side * (1.0 + INSIDE), (button.size.y - side) / 2.0)
	else:
		size = Vector2(side, side)
		position = button.size - size * (1.0 - OVERHANG)


static func _make_backdrop() -> StyleBoxFlat:
	var tile: StyleBoxFlat = StyleBoxFlat.new()
	tile.bg_color = FogView.FOG
	tile.set_corner_radius_all(CORNER)
	return tile
