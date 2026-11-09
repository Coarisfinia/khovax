class_name ActionGlyph
extends Control
## A hint on a button (#583): the glyph of the key or controller button that presses it, for the
## device in use (DeviceInUse): inside a button with words, at its right end, where its words leave
## room for it, and over the bottom right corner of an icon button or one whose words fill it. On
## touch, where the button itself is tapped, it shows only a gesture that presses it too (a pinch,
## InputGlyphs.GESTURES), and it shows none while the button is hidden or rests; with
## `only_focused`,
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
## How opaque a glyph's pixel has to be to count as part of its shape, for its backdrop: low
## enough that the d-pad's faint arms count too.
const SHAPE_ALPHA: float = 0.25

## Each glyph's backdrop (glyph_backdrop), by glyph.
static var _backdrops: Dictionary[Texture2D, Texture2D] = {}

## The InputMap action whose key or button the glyph shows.
var action: StringName = &""
## Whether it shows only while its button has the focus.
var only_focused: bool = false
## The glyph shown now, or null while none shows.
var texture: Texture2D


func _process(_delta: float) -> void:
	follow()


func _draw() -> void:
	if texture == null:
		return
	draw_on(self, texture, Rect2(Vector2.ZERO, size))


## Draws `glyph` in `area` of `canvas` on its rounded fog backdrop, as a hint drawn by hand does
## (the roster's squares, the Survey's buttons, #1192), faded to `alpha`.
static func draw_on(canvas: CanvasItem, glyph: Texture2D, area: Rect2, alpha: float = 1.0) -> void:
	var backdrop: Texture2D = glyph_backdrop(glyph)
	if backdrop != null:
		canvas.draw_texture_rect(backdrop, area, false, Color(FogView.FOG, alpha))
	canvas.draw_texture_rect(glyph, area, false, Color(Toon.INK, alpha))


## The fog under a glyph: its own outline filled in (owner, on #1212), so its open parts (the
## letters cut out of a key) show the fog, not what lies behind, and nothing of it shows past the
## glyph's edge, round or square. Made once per glyph; null where the glyph's pixels can't be read.
static func glyph_backdrop(glyph: Texture2D) -> Texture2D:
	if not _backdrops.has(glyph):
		_backdrops[glyph] = _filled(glyph.get_image())
	return _backdrops[glyph]


## `image`'s shape with its holes filled: white wherever no clear path leads from the edge, and as
## clear as the image along its outline, so the edge stays smooth.
static func _filled(image: Image) -> Texture2D:
	if image == null or image.is_empty():
		return null
	var shape: Image = image.duplicate() as Image
	if shape.is_compressed():
		var _plain: Error = shape.decompress()
	shape.convert(Image.FORMAT_RGBA8)
	var width: int = shape.get_width()
	var outside: PackedByteArray = _outside(shape)
	for y: int in shape.get_height():
		for x: int in width:
			var alpha: float = shape.get_pixel(x, y).a if outside[y * width + x] == 1 else 1.0
			shape.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(shape)


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
	var inside: float = minf(side, button.size.y * INSIDE_HEIGHT)
	# Its words stand in the middle, so the room on either side of them is half what they leave.
	var room: float = (button.size.x - button.get_minimum_size().x) / 2.0
	if button.size.x > button.size.y * 2.0 and room >= inside * (1.0 + INSIDE):
		# A button with words and room beside them: at its right end, inside it.
		size = Vector2(inside, inside)
		position = Vector2(button.size.x - inside * (1.0 + INSIDE), (button.size.y - inside) / 2.0)
	else:
		size = Vector2(side, side)
		position = button.size - size * (1.0 - OVERHANG)


## Which of `shape`'s pixels (row by row, 1 for yes) lie outside it: every clear one reached from
## the edge through clear ones.
static func _outside(shape: Image) -> PackedByteArray:
	var width: int = shape.get_width()
	var height: int = shape.get_height()
	var outside: PackedByteArray = PackedByteArray()
	var _sized: int = outside.resize(width * height)
	var open: Array[Vector2i] = []
	for x: int in width:
		open.append_array([Vector2i(x, 0), Vector2i(x, height - 1)])
	for y: int in height:
		open.append_array([Vector2i(0, y), Vector2i(width - 1, y)])
	while not open.is_empty():
		var at: Vector2i = open.pop_back()
		var index: int = at.y * width + at.x
		if outside[index] == 1 or shape.get_pixelv(at).a >= SHAPE_ALPHA:
			continue
		outside[index] = 1
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = at + step
			if next.x >= 0 and next.y >= 0 and next.x < width and next.y < height:
				open.append(next)
	return outside
