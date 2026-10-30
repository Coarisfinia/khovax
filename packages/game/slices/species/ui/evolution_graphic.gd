class_name EvolutionGraphic
extends HBoxContainer
## How a dominated monster evolves (#1796), as a picture rather than a line: its current form on
## the left (its first type's badge, larger, over its species' name), then an arrow to the right
## with what the evolution takes shown above it as an item (its material, with how many of the one
## it needs the player holds) and the level below it, and at the arrow's end a question mark in a
## dark circle for the form that's still unknown (UnknownFormMark). The item is a button: hovering
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
## The level it evolves at, as the line below the arrow says it. Kept here so tests can read it.
var level_line: String = ""
var _form: VBoxContainer
var _form_name: Label
var _badge: TypeBadge
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
	var unknown: VBoxContainer = _column()
	var mark: UnknownFormMark = UnknownFormMark.new()
	mark.fonts = FORM_FONTS
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	unknown.add_child(mark)
	var unknown_name: Label = _centered()
	unknown_name.text = tr("Unknown")
	unknown.add_child(unknown_name)


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
	var first_type: String = types[0] if not types.is_empty() else ""
	if _badge == null or _badge.tooltip_text != first_type:
		if _badge != null:
			_form.remove_child(_badge)
			_badge.queue_free()
		_badge = TypeBadge.new(first_type)
		_badge.fonts = FORM_FONTS
		_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_form.add_child(_badge)
		_form.move_child(_badge, 0)
	item.text = held_text(holds)
	level_line = TranslationServer.tr("Level {level}").format({ "level": level })
	_level.text = level_line
	card.show_lines([given, material_text(given, holds), level_text(level)])


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
