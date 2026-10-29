class_name CharacterTab
extends ScrollContainer
## The menu's Character tab (#391): the player's personal color (#233) on a freeform color wheel,
## with RGB sliders and a hex field to type it in, kept in their profile and shown on their circle
## at once. Its Auto button hands the color back to the world's default (PersonalColor.of), and a
## line says which one is in use, in words (#68). Below it, the player's standing with each faction
## (#533, FactionStandingsPanel), then their dominated monsters (#400, DominatedMonstersList), with
## the selected one's stats in a pane beside them, or below them on a phone held upright
## (MonsterDetails, #430), where it ascends (#1235), and its development web, where the player takes
## its nodes (DevelopmentWebView, #679), then their materials (MaterialsList, #295). The panels of
## slices after the menu's (the player's Might above their standing, their gear above their
## materials) are handed in by game/ (`add_panel`, #1614), so the menu never names those slices.
## Above them all, the character's name
## (#399): typed into a field and kept once confirmed (Enter, or leaving the field), with a line
## that says in words why a name was refused. It scrolls when the screen is too short. Its layout
## lives in its scene, character_tab.tscn (#437): this script keeps only what it does, and adds the
## panels that are built from their own classes.

## The tab's text was sized to `font` pixels (`fit`): the panels handed in follow it.
signal fitted(font: int)

## The wheel's side, in font sizes, so it grows with the text on a phone.
const WHEEL_FONTS: float = 10.0

## The driver: whose world gives the default and which slot is this machine's player's.
var driver: Session
## What this machine's player's profile does for the tab, handed in by the profile (#1613).
var profile: CharacterProfile = CharacterProfile.new()
## The player's dominated monsters.
var monsters: DominatedMonstersList
## What the tab says the color is now: auto_text() or chosen_text(). Kept here so tests can read
## it.
var shown: String = ""
## The player's standing with each faction, below their Might (#533).
var factions: FactionStandingsPanel
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
	factions = FactionStandingsPanel.new()
	_column.add_child(factions)
	monsters = DominatedMonstersList.new()
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
	var _ascend: int = monsters.details.ascend_chosen.connect(ascend)
	# The selected monster's development web, below the monsters (#679).
	var development: DevelopmentWebView = DevelopmentWebView.new()
	_column.add_child(development)
	var _followed: int = monsters.monster_shown.connect(development.show_monster)
	var _chosen: int = development.node_chosen.connect(take_node)
	materials = MaterialsList.new()
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
	if profile.keep_color.is_valid():
		profile.keep_color.call(PersonalColor.number_of(color))
	_show_state()


## Takes the node `node` of the monster `short_id`'s development web, as pressing it does.
func take_node(short_id: String, node: String) -> void:
	if profile.keep_node.is_valid():
		profile.keep_node.call(short_id, node)
	monsters.refresh()


## Ascends the monster `short_id` into its species' grown form (#1235), as its Ascend button does,
## and says so below its details once it has.
func ascend(short_id: String) -> void:
	if not profile.keep_ascension.is_valid():
		return
	var monster: DominatedMonster = monsters.monster_by(short_id)
	var before: String = monster.species if monster != null else ""
	profile.keep_ascension.call(short_id)
	if monster != null and monster.species != before:
		var known: Dictionary[String, Species] = SpeciesContent.cached().species
		var from: String = tr(known[before].name) if known.has(before) else before
		var now: String = monster.species
		var into: String = tr(known[now].name) if known.has(now) else now
		monsters.details.tell_ascended(tr(MonsterDetails.ASCENDED_TEXT) % [from, into])
	monsters.refresh()


## Hands the color back to the world's default, as the Auto button does.
func choose_auto() -> void:
	if profile.keep_auto.is_valid():
		profile.keep_auto.call()
	refresh()


## Names the character `typed`, as confirming the field does; shows why a name was refused.
func choose_name(typed: String) -> void:
	name_note.text = profile.keep_name.call(typed) if profile.keep_name.is_valid() else ""
	if name_note.text.is_empty():
		fill_name()


## Fills the name field with the name the profile keeps; nothing without a profile.
func fill_name() -> void:
	if profile.kept_name.is_valid():
		name_field.text = profile.kept_name.call()


## Keeps a name once it's confirmed. Its length limit is the profile's, handed in with it
## (ProfilePanelsTie), so it isn't set in the scene.
func _set_up_name() -> void:
	var _submitted: int = name_field.text_submitted.connect(choose_name)
	var _left: int = name_field.focus_exited.connect(func() -> void: choose_name(name_field.text))


## Sizes the wheel for text of `font` pixels, and tells the panels handed in (`fitted`).
func fit(font: int) -> void:
	var wheel: int = roundi(font * WHEEL_FONTS)
	picker.add_theme_constant_override("sv_width", wheel)
	picker.add_theme_constant_override("sv_height", wheel)
	fitted.emit(font)


## Puts `panel`, from a slice after the menu's, in the column right above `below`, one of the
## panels the tab builds itself (#1614).
func add_panel(panel: Control, below: Control) -> void:
	_column.add_child(panel)
	_column.move_child(panel, below.get_index())


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
	var auto: bool = not profile.chose_color.is_valid() or not profile.chose_color.call()
	shown = auto_text() if auto else chosen_text()
	_state.text = shown


## What the tab says while Auto picks the color.
func auto_text() -> String:
	return tr("Auto: this world's color")


## What the tab says while the player picked the color.
func chosen_text() -> String:
	return tr("Your own color")
