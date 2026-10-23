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
## How much lighter than the fog a filled pill is, and how round its ends (round enough for any
## height).
const PILL_LIGHT: float = 0.6
const PILL_CORNER: int = 99
## How faded the names of the tabs not chosen are.
const UNCHOSEN_ALPHA: float = 0.7

static var _theme: Theme


## The UI's theme, made once: labels, rich text and buttons in ink, their icons too, buttons
## rounded with a hover and a press.
static func theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_theme.set_color("font_color", "Label", Toon.INK)
		_theme.set_color("default_color", "RichTextLabel", Toon.INK)
		for type: String in ["Button", "CheckButton", "OptionButton"]:
			_theme.set_color("font_color", type, Toon.INK)
			_theme.set_color("font_hover_color", type, Toon.INK)
			_theme.set_color("font_pressed_color", type, Toon.INK)
			_theme.set_color("font_focus_color", type, Toon.INK)
			# Icons are white shapes (#459), drawn in ink like the text, faded while disabled.
			for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
				_theme.set_color("icon_%s_color" % state, type, Toon.INK)
			_theme.set_color("icon_disabled_color", type, Color(Toon.INK, UNCHOSEN_ALPHA))
			_theme.set_stylebox("normal", type, _button(FogView.FOG))
			_theme.set_stylebox("hover", type, _button(FogView.FOG.lightened(HOVER)))
			_theme.set_stylebox("pressed", type, _button(FogView.FOG.darkened(PRESSED)))
			_theme.set_stylebox("focus", type, _focus())
		_style_tabs(_theme)
	return _theme


## The menu's tabs (#437): rounded on top, in ink on the fog. The chosen tab stands out by shape,
## not colour alone (#68): it's the fog itself with a thicker ink border and no line below, open to
## its page; the others are a shade darker, thin-bordered, closed below, their names a little
## faded.
static func _style_tabs(styled: Theme) -> void:
	styled.set_stylebox("tab_selected", "TabContainer", _tab(FogView.FOG, BORDER * 2, false))
	styled.set_stylebox(
		"tab_unselected",
		"TabContainer",
		_tab(FogView.FOG.darkened(PRESSED), BORDER, true),
	)
	styled.set_stylebox(
		"tab_hovered",
		"TabContainer",
		_tab(FogView.FOG.lightened(HOVER), BORDER, true),
	)
	styled.set_stylebox("tab_focus", "TabContainer", _focus())
	styled.set_color("font_selected_color", "TabContainer", Toon.INK)
	styled.set_color("font_hovered_color", "TabContainer", Toon.INK)
	styled.set_color("font_unselected_color", "TabContainer", Color(Toon.INK, UNCHOSEN_ALPHA))


## A tab filled with `fill`, its ink border `width` wide, rounded on top; `closed` draws its bottom
## edge too.
static func _tab(fill: Color, width: int, closed: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Toon.INK
	style.set_border_width_all(width)
	style.border_width_bottom = BORDER if closed else 0
	style.corner_radius_top_left = CORNER
	style.corner_radius_top_right = CORNER
	style.set_content_margin_all(PADDING / 2.0)
	return style


## A card lying over the game: the fog a little see-through, an ink border, rounded, a shadow.
static func card() -> StyleBoxFlat:
	var style: StyleBoxFlat = _rounded(Color(FogView.FOG, CARD_ALPHA))
	style.border_color = Toon.INK
	style.set_border_width_all(BORDER)
	style.shadow_color = Color(Toon.INK, SHADOW_ALPHA)
	style.shadow_size = SHADOW
	return style


## A small tag (#794): round-ended, in ink, filled lighter than the fog when `filled`, only
## outlined when not.
static func pill(filled: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = FogView.FOG.lightened(PILL_LIGHT)
	style.draw_center = filled
	style.border_color = Toon.INK
	style.set_border_width_all(BORDER)
	style.set_corner_radius_all(PILL_CORNER)
	style.content_margin_left = PADDING / 2.0
	style.content_margin_right = PADDING / 2.0
	style.content_margin_top = BORDER
	style.content_margin_bottom = BORDER
	return style


## A sheet covering the whole screen: the fog, opaque, with `margin` pixels inside.
static func sheet(margin: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = FogView.FOG
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
