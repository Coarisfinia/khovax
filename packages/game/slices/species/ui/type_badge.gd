class_name TypeBadge
extends Control
## A type family's badge (#627): its icon in a circle on its color. Families have no names (#68),
## so both types of a family show the same badge; the icon is what tells them apart, the color
## only backs it (never color alone, #68).

## Each family's icon and color, by family id (TypeChart.FAMILIES).
const ICONS: Array[String] = [
	"icon_magic_swirl",
	"icon_evil_moon",
	"icon_fist",
	"icon_sprout",
	"icon_tornado",
]
const COLORS: Array[Color] = [
	Color("8e44c8"),
	Color("3b3557"),
	Color("a0612b"),
	Color("2f8f3a"),
	Color("2c7fb8"),
]
## The badge's side, in the menu's font size; the icon fills this share of the colored circle
## inside the ring.
const FONTS: float = 1.4
const ICON_SHARE: float = 0.72
## Every circle has a thin light ring inside a thin ink edge (#719), so its edge shows on any
## ground: the ink on the light menu, the light ring on a dark one. Their widths are these shares
## of the badge's side.
const RING_COLOR: Color = Color.WHITE
const RING_SHARE: float = 0.07
const EDGE_SHARE: float = 0.04

## The family it shows, or -1 for a type that isn't on the chart (drawn as nothing).
var family: int = -1
## Its side, in the menu's font size: FONTS beside a type's name, larger where it stands for a
## whole monster (EvolutionGraphic, #1796).
var fonts: float = FONTS


func _init(type: String = "") -> void:
	family = TypeChart.family_of(type)
	tooltip_text = type


func _notification(what: int) -> void:
	# The menu scales its font with the screen; the badge follows it, as the labels beside it do.
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE:
		custom_minimum_size = Vector2.ONE * get_theme_default_font_size() * fonts


func _draw() -> void:
	if family < 0:
		return
	var side: float = minf(size.x, size.y)
	var center: Vector2 = size / 2.0
	var edge: float = maxf(1.0, side * EDGE_SHARE)
	var ring: float = maxf(1.0, side * RING_SHARE)
	var inner: float = side / 2.0 - edge - ring
	# Before layout gives it a size, there is no room for the ring and the colored circle.
	if inner <= 0.0:
		return
	draw_circle(center, side / 2.0, Toon.INK, true, -1.0, true)
	draw_circle(center, side / 2.0 - edge, RING_COLOR, true, -1.0, true)
	draw_circle(center, inner, COLORS[family], true, -1.0, true)
	var icon_side: float = 2.0 * inner * ICON_SHARE
	var icon_rect: Rect2 = Rect2(center - Vector2.ONE * icon_side / 2.0, Vector2.ONE * icon_side)
	draw_texture_rect(ResourcePacks.texture(ICONS[family]), icon_rect, false)


## A row naming `types`, each after its family's badge: what a monster's types show as.
static func row(heading: String, types: Array[String]) -> HBoxContainer:
	var made: HBoxContainer = HBoxContainer.new()
	made.add_child(_plain(heading))
	for type: String in types:
		_add_badged(made, type)
	return made


## Adds `type`'s badge and name to `badged_row`.
static func _add_badged(badged_row: HBoxContainer, type: String) -> void:
	badged_row.add_child(TypeBadge.new(type))
	badged_row.add_child(_plain(type))


## A label that keeps its whole text: these are short, and a trimmed one would shrink to nothing
## in a row.
static func _plain(text: String) -> Label:
	var made: Label = Label.new()
	made.text = text
	made.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return made
