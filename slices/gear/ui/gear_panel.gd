class_name GearPanel
extends VBoxContainer
## The player's gear slots on the menu's Character tab (#690): a button for each slot (GearSlots),
## showing the slot's icon and, in words, the gear in it with its rarity, or that it's empty.
## Pressing one, with a tap, a click or a controller (#438), puts the next piece of the player's
## gear
## for that slot into it, in id order, and empties it after the last. Gear changes anywhere outside
## a fight (owner, #223, Fight): during one, the buttons still show the slots but don't change them,
## and a line says why. It keeps up with the profile and the fight while shown.

const TITLE: String = "Gear"
const EMPTY_TEXT: String = "empty"
const SLOT_TEXT: String = "%s: %s"
const FREE_TEXT: String = "Press a slot to change its gear."
const FIGHT_TEXT: String = "Gear can't be changed during a fight."
## Each slot's icon (#459): white shapes, drawn in ink by the UI's theme.
const ICONS: Dictionary[String, Texture2D] = {
	"ward": preload("res://assets/game-icons/magic-shield.svg"),
	"trap": preload("res://assets/game-icons/wolf-trap.svg"),
	"throw": preload("res://assets/game-icons/berries-bowl.svg"),
}

## Where the fight is: this machine's player's instance.
var driver: Session
## Whose gear is shown: this machine's player's profile.
var holder: ProfileHolder
## What the panel shows: a line per slot, then the line saying whether gear can change. Kept here
## so tests can read it.
var shown: Array[String] = []
## Each slot's button, by slot.
var buttons: Dictionary[String, Button] = {}
## Every piece of gear's data, by id; a piece missing from the data shows its id.
var _items: Dictionary[String, GearItem] = {}
var _note: Label


func _ready() -> void:
	var content: GearContent = GearContent.load_gear()
	if not content.problem.is_empty():
		push_warning("the gear can't be read, so gear shows its ids: " + content.problem)
	_items = content.items
	add_child(GameMenu.label(TITLE))
	for slot: String in GearSlots.SLOTS:
		var button: Button = GameMenu.button("", change.bind(slot))
		button.icon = ICONS[slot]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		buttons[slot] = button
		add_child(button)
	_note = GameMenu.label("")
	add_child(_note)
	refresh()


func _process(_delta: float) -> void:
	# Only while it's shown: the menu is open on the Character tab.
	if is_visible_in_tree():
		refresh()


## Sizes the slots' icons for text of `font` pixels, a little larger than the text.
func fit(font: int) -> void:
	var width: int = roundi(font * GameMenu.ICON_FONTS)
	for slot: String in buttons:
		buttons[slot].add_theme_constant_override("icon_max_width", width)


## Shows the gear in each slot as it is now, and whether it can change.
func refresh() -> void:
	var fighting: bool = in_fight()
	var lines: Array[String] = []
	for slot: String in GearSlots.SLOTS:
		var gear_id: String = _equipped().get(slot, "")
		var line: String = SLOT_TEXT % [slot.capitalize(), _described(gear_id)]
		lines.append(line)
		buttons[slot].text = line
		buttons[slot].disabled = fighting
	_note.text = FIGHT_TEXT if fighting else FREE_TEXT
	lines.append(_note.text)
	shown = lines


## Puts the next piece of the player's gear for `slot` into it, as its button does; nothing during a
## fight.
func change(slot: String) -> void:
	if holder == null or holder.keeper == null or in_fight():
		return
	holder.equip(slot, _next(slot))
	refresh()


## Whether this machine's player is in a fight, where gear can't change.
func in_fight() -> bool:
	if driver == null or driver.state == null or driver.input == null:
		return false
	return Fight.involves(driver.state, driver.input.slot)


## The gear in each slot, by slot: none without a profile.
func _equipped() -> Dictionary[String, String]:
	var none: Dictionary[String, String] = {}
	return holder.keeper.profile.gear.equipped if holder != null and holder.keeper != null else none


## The piece of gear that comes after the one in `slot`: the player's gear for that slot in id
## order, then none ("") after the last.
func _next(slot: String) -> String:
	var choices: Array[String] = []
	for gear_id: String in holder.keeper.profile.gear.owned:
		var item: GearItem = _items.get(gear_id)
		var count: int = holder.keeper.profile.gear.owned[gear_id]
		if item != null and item.slot == slot and count > 0:
			choices.append(gear_id)
	choices.sort()
	choices.append("")
	return choices[(choices.find(_equipped().get(slot, "")) + 1) % choices.size()]


## The gear `gear_id`, in words: its name and rarity, its id where the data lacks it, or EMPTY_TEXT.
func _described(gear_id: String) -> String:
	if gear_id.is_empty():
		return EMPTY_TEXT
	var item: GearItem = _items.get(gear_id)
	return item.described() if item != null else gear_id.capitalize()
