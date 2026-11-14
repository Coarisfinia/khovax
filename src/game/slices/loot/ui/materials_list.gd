class_name MaterialsList
extends VBoxContainer
## The player's materials on the menu's Character tab (#295): each material in their profile with
## how many they have, in id order, each by its name from its data (MaterialContent, #1657), or by
## the name a later slice gives what the profile counts like a material, such as a crafted tonic
## (`names`, #2282). It only reads the profile, and keeps up with it while shown.

## This machine's player's materials (Dictionary[String, int], by id), handed in by the profile
## (ProfilePanelsTie), whose slice comes after this one; none without it.
var materials: Callable = Callable()
## The untranslated name of an entry no material file names (String to String, "" when it names
## none), handed in by game/: the profile counts a crafted tonic like a material (#2090), and the
## tonics' slice comes after this one.
var names: Callable = Callable()
## What the list shows, one line per material. Kept here so tests can read it.
var shown: Array[String] = []
var _rows: VBoxContainer


func _ready() -> void:
	add_child(MenuWidgets.label(tr("Materials")))
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
		var content: MaterialContent = MaterialContent.cached()
		for id: String in ids:
			var line: String = tr("{material}: {count}")
			lines.append(line.format({ "material": _name_of(content, id), "count": held[id] }))
	if lines.is_empty():
		lines.append(tr("No materials yet"))
	if lines == shown:
		return
	shown = lines
	MenuWidgets.show_lines(_rows, lines)


## The name the player reads for the material `id`: its own, or what `names` gives for one no
## material file names, or MaterialContent's unknown material.
func _name_of(content: MaterialContent, id: String) -> String:
	if not content.names.has(id) and names.is_valid():
		var named: String = names.call(id)
		if not named.is_empty():
			return tr(named)
	return content.name_of(id)
