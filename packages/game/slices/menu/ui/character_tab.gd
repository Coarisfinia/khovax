class_name CharacterTab
extends ScrollContainer
## The menu's Character tab (#391): the player's personal color (#233) on a freeform color wheel,
## with RGB sliders and a hex field to type it in, kept in their profile and shown on their circle
## at once. Its Auto button hands the color back to the world's default (PersonalColor.of), and a
## line says which one is in use, in words (#68). Below it, the player's Might and its parts (#509,
## MightPanel) and their standing with each faction (#533, FactionStandingsPanel), then their
## dominated monsters (#400, DominatedMonstersList), with the selected one's stats in a pane beside
## them, or below them on a phone held upright (MonsterDetails, #430), and its development web,
## where the player takes its nodes (DevelopmentWebView, #679), then their gear slots (#690,
## GearPanel) and their materials (MaterialsList, #295). Above them all, the character's name
## (#399): typed into a field and kept once confirmed (Enter, or leaving the field), with a line
## that says in words why a name was refused. It scrolls when the screen is too short. Its layout
## lives in its scene, character_tab.tscn (#437): this script keeps only what it does, and adds the
## panels that are built from their own classes.

## The wheel's side, in font sizes, so it grows with the text on a phone.
const WHEEL_FONTS: float = 10.0
const AUTO_TEXT: String = "Auto: this world's color"
const CHOSEN_TEXT: String = "Your own color"

## The driver: whose world gives the default and which slot is this machine's player's.
var driver: Session
## Whose profile keeps the color.
var holder: ProfileHolder
## The player's dominated monsters.
var monsters: DominatedMonstersList
## What the tab says the color is now: AUTO_TEXT or CHOSEN_TEXT. Kept here so tests can read it.
var shown: String = ""
## The player's Might and its parts, above their monsters (#509).
var might: MightPanel
## The player's standing with each faction, below their Might (#533).
var factions: FactionStandingsPanel
## The player's gear slots, below their monsters (#690).
var gear: GearPanel
## The player's materials, below their gear (#295).
var materials: MaterialsList
## The monsters and their detail pane, side by side or one above the other.
var _pair: BoxContainer

## The wheel, in the scene with no alpha or intensity to pick: the circle is opaque and not lit
## brighter than white, so RGB alone sits beside the wheel's hue, saturation and value.
@onready var picker: ColorPicker = $Middle/Column/Picker
## Hands the color back to Auto.
@onready var auto_button: Button = $Middle/Column/Auto
## The character's name field, and the line saying why a name was refused ("" when it wasn't).
@onready var name_field: LineEdit = $Middle/Column/NameField
@onready var name_note: Label = $Middle/Column/NameNote
@onready var _column: VBoxContainer = $Middle/Column
@onready var _state: Label = $Middle/Column/State


func _ready() -> void:
	_set_up_name()
	var _picked: int = picker.color_changed.connect(_on_picked)
	var _auto: int = auto_button.pressed.connect(choose_auto)
	might = MightPanel.new()
	might.holder = holder
	_column.add_child(might)
	factions = FactionStandingsPanel.new()
	factions.holder = holder
	_column.add_child(factions)
	monsters = DominatedMonstersList.new()
	monsters.holder = holder
	# The monsters beside their detail pane, or above it on a portrait screen (place_details, #430).
	_pair = BoxContainer.new()
	# Both halves share the row: the menu's labels trim rather than ask for a width, so a half that
	# didn't expand would shrink to its buttons.
	monsters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pair.add_child(monsters)
	monsters.details = MonsterDetails.new()
	monsters.details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pair.add_child(monsters.details)
	_column.add_child(_pair)
	# The selected monster's development web, below the monsters (#679).
	var development: DevelopmentWebView = DevelopmentWebView.new()
	_column.add_child(development)
	var _followed: int = monsters.monster_shown.connect(development.show_monster)
	var _chosen: int = development.node_chosen.connect(take_node)
	gear = GearPanel.new()
	gear.driver = driver
	gear.holder = holder
	_column.add_child(gear)
	materials = MaterialsList.new()
	materials.holder = holder
	_column.add_child(materials)


## Shows the color in use, the player's own or the world's default while Auto picks it, and their
## monsters as they are now.
func refresh() -> void:
	monsters.refresh()
	var local: int = driver.input.slot if driver != null and driver.input != null else 0
	picker.color = PersonalColor.shown(driver, local)
	_show_state()


## Keeps `color` as the player's personal color, as picking it on the wheel does. The wheel keeps
## what the player picked rather than the color as saved, so a drag never jitters.
func choose(color: Color) -> void:
	if holder != null:
		holder.choose_color(PersonalColor.number_of(color))
	_show_state()


## Takes the node `node` of the monster `short_id`'s development web, as pressing it does.
func take_node(short_id: String, node: String) -> void:
	if holder != null:
		holder.take_node(short_id, node)
	monsters.refresh()


## Hands the color back to the world's default, as the Auto button does.
func choose_auto() -> void:
	if holder != null:
		holder.choose_color(Profile.AUTO_COLOR)
	refresh()


## Names the character `typed`, as confirming the field does; shows why a name was refused.
func choose_name(typed: String) -> void:
	name_note.text = holder.choose_name(typed) if holder != null else ""
	if name_note.text.is_empty() and holder != null and holder.keeper != null:
		name_field.text = holder.keeper.profile.character_name


## Fills the name field with the profile's name and keeps a name once it's confirmed. Its length
## limit is the profile's (Profile.NAME_LIMIT), so it's set here rather than in the scene.
func _set_up_name() -> void:
	name_field.max_length = Profile.NAME_LIMIT
	if holder != null and holder.keeper != null:
		name_field.text = holder.keeper.profile.character_name
	var _submitted: int = name_field.text_submitted.connect(choose_name)
	var _left: int = name_field.focus_exited.connect(func() -> void: choose_name(name_field.text))


## Sizes the wheel for text of `font` pixels.
func fit(font: int) -> void:
	var wheel: int = roundi(font * WHEEL_FONTS)
	picker.add_theme_constant_override("sv_width", wheel)
	picker.add_theme_constant_override("sv_height", wheel)
	gear.fit(font)


## Puts the detail pane beside the monsters (`beside`, on a landscape screen) or below them, on a
## phone held upright (#430).
func place_details(beside: bool) -> void:
	_pair.vertical = not beside


## Makes the tab's column `width` pixels wide, so the monsters' lines fit.
func fit_width(width: float) -> void:
	_column.custom_minimum_size.x = width


func _on_picked(color: Color) -> void:
	choose(color)


## Says whether the color is the player's own or Auto's.
func _show_state() -> void:
	var auto: bool = holder == null or holder.personal_color() == Profile.AUTO_COLOR
	shown = AUTO_TEXT if auto else CHOSEN_TEXT
	_state.text = shown
