class_name CharacterTab
extends ScrollContainer
## The menu's Character tab (#391): the player's personal color (#233) on a freeform color wheel,
## with RGB sliders and a hex field to type it in, kept in their profile and shown on their circle
## at once. Its Auto button hands the color back to the world's default (PersonalColor.of), and a
## line says which one is in use, in words (#68). Below it, the player's dominated monsters (#400,
## DominatedMonstersList). The character's name follows on this tab later. It scrolls when the
## screen is too short.

## The wheel's side, in font sizes, so it grows with the text on a phone.
const WHEEL_FONTS: float = 10.0
const AUTO_TEXT: String = "Auto: this world's color"
const CHOSEN_TEXT: String = "Your own color"

## The driver: whose world gives the default and which slot is this machine's player's.
var driver: GameDriver
## Whose profile keeps the color.
var holder: ProfileHolder
var picker: ColorPicker
## Hands the color back to Auto.
var auto_button: Button
## The player's dominated monsters.
var monsters: DominatedMonstersList
## What the tab says the color is now: AUTO_TEXT or CHOSEN_TEXT. Kept here so tests can read it.
var shown: String = ""
var _column: VBoxContainer
var _state: Label


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var middle: CenterContainer = CenterContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column = VBoxContainer.new()
	_column.add_child(GameMenu.label("Personal color"))
	_state = GameMenu.label("")
	_column.add_child(_state)
	picker = ColorPicker.new()
	picker.picker_shape = ColorPicker.SHAPE_HSV_WHEEL
	# The circle is opaque and not lit brighter than white: no alpha or intensity to pick, and RGB
	# alone beside the wheel's hue, saturation and value.
	picker.edit_alpha = false
	picker.edit_intensity = false
	picker.color_modes_visible = false
	picker.presets_visible = false
	picker.sampler_visible = false
	# The column is as wide as the monsters' lines (fit_width); the wheel stays in its middle.
	picker.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var _picked: int = picker.color_changed.connect(_on_picked)
	_column.add_child(picker)
	auto_button = GameMenu.button("Auto", choose_auto)
	auto_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_column.add_child(auto_button)
	monsters = DominatedMonstersList.new()
	monsters.holder = holder
	_column.add_child(monsters)
	middle.add_child(_column)
	add_child(middle)


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


## Hands the color back to the world's default, as the Auto button does.
func choose_auto() -> void:
	if holder != null:
		holder.choose_color(Profile.AUTO_COLOR)
	refresh()


## Sizes the wheel for text of `font` pixels.
func fit(font: int) -> void:
	var wheel: int = roundi(font * WHEEL_FONTS)
	picker.add_theme_constant_override("sv_width", wheel)
	picker.add_theme_constant_override("sv_height", wheel)


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
