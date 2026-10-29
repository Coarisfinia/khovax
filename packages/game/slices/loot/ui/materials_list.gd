class_name MaterialsList
extends VBoxContainer
## The player's materials on the menu's Character tab (#295): each material in their profile with
## how many they have, in id order. Materials have no names of their own yet (MaterialContent,
## #774),
## so each shows by its id in words. It only reads the profile, and keeps up with it while shown.

const TITLE: String = "Materials"
const NONE_TEXT: String = "No materials yet"

## This machine's player's materials (Dictionary[String, int], by id), handed in by the profile
## (ProfilePanelsTie), whose slice comes after this one; none without it.
var materials: Callable = Callable()
## What the list shows, one line per material. Kept here so tests can read it.
var shown: Array[String] = []
var _rows: VBoxContainer


func _ready() -> void:
	add_child(MenuWidgets.label(TITLE))
	_rows = VBoxContainer.new()
	add_child(_rows)
	refresh()


func _process(_delta: float) -> void:
	# Only while the tab is shown: the menu is open on it.
	if is_visible_in_tree():
		refresh()


## Shows the materials as they are now; builds the rows anew only when that changed.
func refresh() -> void:
	var lines: Array[String] = []
	if materials.is_valid():
		var held: Dictionary[String, int] = materials.call()
		var ids: Array[String] = []
		ids.assign(held.keys())
		ids.sort()
		for id: String in ids:
			lines.append("%s: %d" % [id.capitalize(), held[id]])
	if lines.is_empty():
		lines.append(NONE_TEXT)
	if lines == shown:
		return
	shown = lines
	MenuWidgets.show_lines(_rows, lines)
