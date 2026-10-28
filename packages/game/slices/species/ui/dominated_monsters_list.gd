class_name DominatedMonstersList
extends VBoxContainer
## The player's dominated monsters on the menu's Character tab (#400): every one in their profile,
## by its species' name and its level. The three they carry come first, in the order they come in
## (#53), the first of them their companion (#338); each line says in words whether it's carried
## and where, never by color alone (#68). It keeps up with the profile while shown. The player
## orders them (#430): a row dragged onto another takes its place, and each row's up and down
## buttons move it one place, which a controller reaches too (#438). The first three are carried.
## A monster with a knot of its development web to take carries a mark in its row (KnotMark, #1443).
## Whatever else shows the selected monster, like its development web (#679), follows
## `monster_shown`.

## The selected monster as it is now, or null: told each time the list refreshes.
signal monster_shown(monster: DominatedMonster)

const TITLE: String = "Monsters"
const NONE_TEXT: String = "No dominated monsters yet"
const COMPANION_TEXT: String = "Carried 1, companion: "
const CARRIED_TEXT: String = "Carried %d: "
const RESTING_TEXT: String = "Not carried: "
## The buttons that move a monster one place up or down in the order: their icons (#584) and
## their words on hover.
const UP_ICON: Texture2D = preload("res://assets/game-icons/plain-arrow-up.svg")
const DOWN_ICON: Texture2D = preload("res://assets/game-icons/plain-arrow-down.svg")
const UP_TIP: String = "Move up"
const DOWN_TIP: String = "Move down"

## Whose monsters are shown: this machine's player's profile.
var holder: ProfileHolder
## What the list shows, one line per monster. Kept here so tests can read it.
var shown: Array[String] = []
## The monster each row shows, by short id (#754), in the rows' order.
var shown_ids: Array[String] = []
## Whether each row carries the knot mark (#1443), in the rows' order.
var marked: Array[bool] = []
## The monster whose stats the detail pane shows, by short id: the first one until the player
## taps, clicks or moves the focus onto another (#430).
var selected: String = ""
## The pane that shows the selected monster's stats, if the tab has one.
var details: MonsterDetails
## Each species' data and each ability's name with its path mark in words (#471), by id; a species
## missing from the data shows its id.
var _species: Dictionary[String, Species] = {}
var _abilities: Dictionary[String, String] = {}
## What each species ascends into (#1235), by id.
var _ascensions: Dictionary[String, SpeciesAscension] = {}
var _rows: VBoxContainer


func _ready() -> void:
	var species: SpeciesContent = SpeciesContent.cached()
	if not species.problem.is_empty():
		push_warning("the species can't be read, so monsters show their ids: " + species.problem)
	_species = species.species
	_ascensions = species.ascensions
	_abilities = MonsterDetails.all_ability_names()
	add_child(MenuWidgets.label(TITLE))
	_rows = VBoxContainer.new()
	add_child(_rows)
	_show([NONE_TEXT], [])


func _process(_delta: float) -> void:
	# Only while it's shown: the menu is open on the Character tab.
	if is_visible_in_tree():
		refresh()


## Shows the monsters as they are now; builds the rows anew only when that changed.
func refresh() -> void:
	var lines: Array[String] = []
	var ids: Array[String] = []
	var marks: Array[bool] = []
	if holder != null and holder.keeper != null:
		ids = holder.keeper.profile.order()
		lines = _lines_of(holder.keeper.profile, ids)
		for short_id: String in ids:
			marks.append(KnotMark.waits(holder.keeper.profile.monster_of(short_id)))
	if lines.is_empty():
		lines.append(NONE_TEXT)
	if lines != shown or ids != shown_ids or marks != marked:
		_show(lines, ids, marks)
	if not shown_ids.has(selected):
		selected = shown_ids[0] if not shown_ids.is_empty() else ""
	_show_details()


## Shows the monster `short_id`'s stats in the detail pane, as a tap, a click or the focus does.
func select(short_id: String) -> void:
	selected = short_id
	_show_details()


func _show_details() -> void:
	var monster: DominatedMonster = null
	if holder != null and holder.keeper != null:
		monster = holder.keeper.profile.monster_of(selected)
	monster_shown.emit(monster)
	if details == null:
		return
	var species: Species = null
	var ascension: SpeciesAscension = null
	var holds: int = 0
	if monster != null:
		species = _species.get(monster.species)
		ascension = _ascensions.get(monster.species)
	if ascension != null:
		holds = holder.keeper.profile.materials.get(ascension.material, 0)
	details.show_monster(monster, species, _abilities, ascension, holds)


## A line for each of `profile`'s dominated monsters in `ids`, the player's order: the carried
## ones first, then the rest.
func _lines_of(profile: Profile, ids: Array[String]) -> Array[String]:
	var lines: Array[String] = []
	for place: int in ids.size():
		var prefix: String = RESTING_TEXT
		if place < profile.carried.size():
			prefix = COMPANION_TEXT if place == 0 else CARRIED_TEXT % (place + 1)
		lines.append(prefix + _described(profile.monster_of(ids[place])))
	return lines


## Moves the monster `short_id` to `place` in the player's order, as its buttons and a drag do.
func move(short_id: String, place: int) -> void:
	if holder != null:
		holder.move_monster(short_id, place)
	refresh()


## `monster`'s species name and level, in words: every one in the order is there, as the save
## guarantees every carried one is (ProfileSave).
func _described(monster: DominatedMonster) -> String:
	var known: Species = _species.get(monster.species)
	return "%s, level %d" % [known.name if known != null else monster.species, monster.level]


## Builds a row for each of `lines`, showing the monster of the same place in `ids`, if any, with
## the knot mark where `marks` says so.
func _show(lines: Array[String], ids: Array[String], marks: Array[bool] = []) -> void:
	shown = lines
	shown_ids = ids
	marked = marks
	# Out of the list at once, so its buttons and places are only ever the current ones.
	for row: Node in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	for place: int in lines.size():
		var short_id: String = ids[place] if place < ids.size() else ""
		_rows.add_child(_row(lines[place], short_id, place, place < marks.size() and marks[place]))


## A monster's row: its line, which can be dragged onto another row, the knot mark below it if
## `with_mark`, and its up and down buttons. Without a monster (`short_id` ""), the line alone.
func _row(line: String, short_id: String, place: int, with_mark: bool) -> Control:
	var text: Label = MenuWidgets.label(line)
	if short_id.is_empty():
		return text
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A tap or a click shows it in the detail pane, and so does a controller's focus (#438).
	text.focus_mode = Control.FOCUS_ALL
	var _focused: int = text.focus_entered.connect(select.bind(short_id))
	var parts: Array[Control] = [text]
	var row: HBoxContainer = HBoxContainer.new()
	if with_mark:
		# Below its line, so the line keeps its width and still says which monster it is.
		var column: VBoxContainer = VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(text)
		parts.append(KnotMark.new())
		column.add_child(parts[1])
		row.add_child(column)
	else:
		row.add_child(text)
	# The mark takes a tap, a click or a drag as its line does, so it never leaves a dead spot.
	for part: Control in parts:
		part.mouse_filter = Control.MOUSE_FILTER_STOP
		var _tapped: int = part.gui_input.connect(_on_row_input.bind(short_id))
		part.set_drag_forwarding(
			func(_at: Vector2) -> Variant: return short_id,
			func(_at: Vector2, data: Variant) -> bool: return data is String,
			func(_at: Vector2, data: Variant) -> void: _dropped(data, place),
		)
	row.add_child(MenuWidgets.icon_button(UP_ICON, UP_TIP, move.bind(short_id, place - 1)))
	row.add_child(MenuWidgets.icon_button(DOWN_ICON, DOWN_TIP, move.bind(short_id, place + 1)))
	return row


## A row's monster, dragged and dropped onto the row in `place`: it moves there.
func _dropped(data: Variant, place: int) -> void:
	var short_id: String = data
	move(short_id, place)


func _on_row_input(event: InputEvent, short_id: String) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		select(short_id)
