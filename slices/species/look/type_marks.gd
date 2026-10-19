class_name TypeMarks
extends RefCounted
## The type chart's marks on a strike's damage (#701): after the number, ▲ for each of the struck
## monster's types the strike is strong against and ▼ for each it's weak against, so a ×4 hit
## shows ▲▲, and the text is tinted to match: never color alone (#68). The game's font has no
## such glyphs, so each mark is a sprite facing the camera, a triangle drawn from SVG in the text's
## ink.

const STRONG_TINT: Color = Color(1.0, 0.7, 0.28)
const WEAK_TINT: Color = Color(0.6, 0.74, 0.9)
## A mark's side and the gap before each mark, in the text's pixels.
const SIDE: float = 36.0
const GAP: float = 8.0
## How much finer than the text's pixels a mark's texture is drawn, so its edges stay smooth.
const DETAIL: float = 2.0
## A triangle pointing up in a square of side 36, its outline in ink.
const UP_SVG: String = (
	"<svg xmlns='http://www.w3.org/2000/svg' width='36' height='36'><path d='M18 4 L33 31 L3 31 Z'"
	+ " fill='white' stroke='#%s' stroke-width='4' stroke-linejoin='round'/></svg>"
)

static var _up: Texture2D
static var _down: Texture2D


## Marks `label`'s first line with `strong` (TypeEffectivenessFeature.strong_against): one mark
## per type after the line, and the label tinted by which there are more of. No marks, no tint.
static func add_to(label: Label3D, strong: Array[bool]) -> void:
	var font: Font = label.font if label.font != null else ThemeDB.fallback_font
	var first: String = label.text.get_slice("\n", 0)
	var width: float = font.get_string_size(first, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x
	# The label's lines are centered on its origin, so the first one sits half the others higher.
	var line: float = font.get_height(label.font_size) + label.line_spacing
	var height: float = label.text.count("\n") * line / 2.0
	var lean: int = 0
	for each: bool in strong:
		lean += 1 if each else -1
	if lean != 0:
		label.modulate = STRONG_TINT if lean > 0 else WEAK_TINT
	for index: int in strong.size():
		var mark: Sprite3D = _mark(label, strong[index])
		var across: float = width / 2.0 + GAP + index * (SIDE + GAP) + SIDE / 2.0
		mark.offset = Vector2(across, height) * DETAIL
		label.add_child(mark)


## One mark for `label`, pointing up if `strong`, tinted and drawn over everything as its text is.
static func _mark(label: Label3D, strong: bool) -> Sprite3D:
	var mark: Sprite3D = Sprite3D.new()
	mark.texture = _texture(strong)
	mark.pixel_size = label.pixel_size / DETAIL
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.render_priority = label.render_priority
	mark.modulate = label.modulate
	return mark


## The texture of a mark pointing up (`strong`) or down, drawn once.
static func _texture(strong: bool) -> Texture2D:
	if _up == null:
		var svg: String = UP_SVG % Toon.INK.to_html(false)
		var image: Image = Image.new()
		var _loaded: Error = image.load_svg_from_string(svg, DETAIL)
		_up = ImageTexture.create_from_image(image)
		image.flip_y()
		_down = ImageTexture.create_from_image(image)
	return _up if strong else _down
