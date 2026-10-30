class_name EvolutionGraphic
extends HBoxContainer
## How a dominated monster evolves (#1796), as a picture rather than a line: its current form on
## the left (its first type's badge, larger, over its species' name), then an arrow to the right
## with what the evolution takes shown above it as an item (its material, with how many of the one
## it needs the player holds) and the level below it, and at the arrow's end the form it ascends
## into: once the player knows it (#1801), like the current form, its first type's badge over its
## name; until then a question mark in a dark circle (UnknownFormMark). The item is a button:
## hovering
## it, giving it a controller's focus or tapping it opens a HoverCard saying what it is and what
## the evolution needs. MonsterDetails shows it for a monster whose species ascends (#1235).

## The item's icon: materials have no icons of their own yet, so a bag stands for any.
const ITEM_ICON: Texture2D = preload("res://assets/game-icons/swap-bag.svg")
## Both forms' sides, and the arrow's shortest length, in the menu's font size.
const FORM_FONTS: float = 2.6
const ARROW_FONTS: float = 4.0
## The room between the forms and the arrow, in the menu's font size.
const GAP_FONTS: float = 0.5

## The item standing for what the evolution takes, and the card it opens.
var item: Button
var card: HoverCard
## The level it evolves at, as the line below the arrow says it, and the name of the form it
## ascends into, "" while that's unknown. Kept here so tests can read them.
var level_line: String = ""
var next_form: String = ""
## What stands for the next form while it's unknown, and its badge once it's known (null before).
var mark: UnknownFormMark
var next_badge: TypeBadge
var _form: VBoxContainer
var _form_name: Label
var _badge: TypeBadge
var _next: VBoxContainer
var _next_name: Label
var _arrow: EvolutionArrow
var _level: Label


func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	_form = _column()
	_form_name = _centered()
	_form.add_child(_form_name)
	var middle: VBoxContainer = _column()
	item = MenuWidgets.with_icon(MenuWidgets.button("", func() -> void: pass), ITEM_ICON)
	item.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	middle.add_child(item)
	card = HoverCard.attach(item)
	_arrow = EvolutionArrow.new()
	middle.add_child(_arrow)
	_level = _centered()
	middle.add_child(_level)
	_next = _column()
	mark = UnknownFormMark.new()
	mark.fonts = FORM_FONTS
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_next.add_child(mark)
	_next_name = _centered()
	_next_name.text = tr("Unknown")
	_next.add_child(_next_name)


func _notification(what: int) -> void:
	# The arrow and the gaps grow with the menu's font, as the forms beside them do.
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE:
		var font_size: float = get_theme_default_font_size()
		_arrow.custom_minimum_size.x = ARROW_FONTS * font_size
		var gap: int = roundi(GAP_FONTS * font_size)
		# An override changes the theme again: set it only when it differs, or it never settles.
		if get_theme_constant("separation") != gap:
			add_theme_constant_override("separation", gap)


## Shows a monster of the species named `species_name`, of `types`, that ascends at `level` given
## one of the material named `given`, of which the player `holds` this many.
func show_evolution(
	species_name: String,
	types: Array[String],
	given: String,
	level: int,
	holds: int,
) -> void:
	_form_name.text = species_name
	_badge = _badge_in(_form, _badge, types)
	item.text = held_text(holds)
	level_line = TranslationServer.tr("Level {level}").format({ "level": level })
	_level.text = level_line
	card.show_lines([given, material_text(given, holds), level_text(level)])


## Shows the form it ascends into as the species named `next_name`, of `next_types`, or as a
## question mark for a `next_name` of "": the player doesn't know that species yet.
func show_next(next_name: String, next_types: Array[String]) -> void:
	next_form = next_name
	var known: bool = not next_name.is_empty()
	_next_name.text = next_name if known else tr("Unknown")
	mark.visible = not known
	if known:
		next_badge = _badge_in(_next, next_badge, next_types)
	if next_badge != null:
		next_badge.visible = known


## How many of the one material it needs the player `holds`, on the item.
static func held_text(holds: int) -> String:
	return TranslationServer.tr("{held}/{needed}").format({ "held": holds, "needed": 1 })


## At which `level` it ascends, on the item's card.
static func level_text(level: int) -> String:
	return TranslationServer.tr("It ascends at level {level}").format({ "level": level })


## Its material, `given`, and how many of it the player `holds`, on the item's card, through tr_n()
## so a language picks its plural form by the count (#1709).
static func material_text(given: String, holds: int) -> String:
	return TranslationServer.tr_n(
		"Given one {material}: you hold {count}",
		"Given one {material}: you hold {count}",
		holds,
	).format({ "material": given, "count": holds })


## The badge of the first of `types` at the top of `column`, in place of `old` (null for none),
## which stays when it already shows that type: the graphic is shown anew every frame.
static func _badge_in(column: VBoxContainer, old: TypeBadge, types: Array[String]) -> TypeBadge:
	var first_type: String = types[0] if not types.is_empty() else ""
	if old != null and old.tooltip_text == first_type:
		return old
	if old != null:
		column.remove_child(old)
		old.queue_free()
	var made: TypeBadge = TypeBadge.new(first_type)
	made.fonts = FORM_FONTS
	made.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(made)
	column.move_child(made, 0)
	return made


## A column of the graphic, added to it, its parts centered.
func _column() -> VBoxContainer:
	var made: VBoxContainer = VBoxContainer.new()
	made.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(made)
	return made


## A label centered in its column, keeping its whole text: a trimmed one would shrink to nothing.
static func _centered() -> Label:
	var made: Label = Label.new()
	made.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return made
