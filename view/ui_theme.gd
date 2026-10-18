class_name UiTheme
extends RefCounted
## The game's one look for its UI (#437): every panel, card and button takes its colors, corners and
## spacing from here, instead of each screen styling itself. Ink on the fog's color, like the
## world's outlines; rounded corners and a soft shadow so a panel reads as lying over the game.

## How round a panel's or button's corners are, in pixels.
const CORNER: int = 10
## How wide the ink border is, in pixels.
const BORDER: int = 2
## The space inside a panel or card, in pixels.
const PADDING: int = 12
## How far a panel's shadow reaches, in pixels, and how dark it is.
const SHADOW: int = 6
const SHADOW_ALPHA: float = 0.25
## How see-through a card over the game is: the world shows through a little.
const CARD_ALPHA: float = 0.82
## How much lighter a hovered button is, and how much darker a pressed one.
const HOVER: float = 0.08
const PRESSED: float = 0.12

static var _theme: Theme


## The UI's theme, made once: labels and buttons in ink, buttons rounded with a hover and a press.
static func theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_theme.set_color("font_color", "Label", Toon.INK)
		for type: String in ["Button", "CheckButton", "OptionButton"]:
			_theme.set_color("font_color", type, Toon.INK)
			_theme.set_color("font_hover_color", type, Toon.INK)
			_theme.set_color("font_pressed_color", type, Toon.INK)
			_theme.set_color("font_focus_color", type, Toon.INK)
			_theme.set_stylebox("normal", type, _button(Boot.FOG))
			_theme.set_stylebox("hover", type, _button(Boot.FOG.lightened(HOVER)))
			_theme.set_stylebox("pressed", type, _button(Boot.FOG.darkened(PRESSED)))
			_theme.set_stylebox("focus", type, _focus())
	return _theme


## A card lying over the game: the fog a little see-through, an ink border, rounded, a shadow.
static func card() -> StyleBoxFlat:
	var style: StyleBoxFlat = _rounded(Color(Boot.FOG, CARD_ALPHA))
	style.border_color = Toon.INK
	style.set_border_width_all(BORDER)
	style.shadow_color = Color(Toon.INK, SHADOW_ALPHA)
	style.shadow_size = SHADOW
	return style


## A sheet covering the whole screen: the fog, opaque, with `margin` pixels inside.
static func sheet(margin: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Boot.FOG
	style.set_content_margin_all(margin)
	return style


static func _button(fill: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = _rounded(fill)
	style.border_color = Toon.INK
	style.set_border_width_all(BORDER)
	return style


## Keyboard and controller focus: a thicker ink ring, so it shows without color alone (#68).
static func _focus() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = Toon.INK
	style.set_border_width_all(BORDER * 2)
	style.set_corner_radius_all(CORNER)
	return style


static func _rounded(fill: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(CORNER)
	style.set_content_margin_all(PADDING)
	return style
