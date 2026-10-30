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

## The buttons that move a monster one place up or down in the order: their icons (#584); their
## words on hover say so (_row).
const UP_ICON: String = "icon_plain_arrow_up"
const DOWN_ICON: String = "icon_plain_arrow_down"

## This machine's player's monsters, handed in by the profile (ProfilePanelsTie), whose slice comes
## after this one; none without it: their short ids in their order and the ones they carry (each an
## Array[String]), the monster of a short id (a DominatedMonster, or null), their materials
## (Dictionary[String, int]: what an ascension costs, #1235), and what moves a monster to a place in
## their order.
var order: Callable = Callable()
## Whether this machine's player knows a species, by id (a bool), well enough to see its name and
## types (#1801): handed in by the codex (KnownFormsTie), whose slice comes after this one; none
## known without it. The details show the form a monster ascends into only then.
var knows: Callable = Callable()
var carried: Callable = Callable()
var monster_of: Callable = Callable()
var materials: Callable = Callable()
var reorder: Callable = Callable()
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
	add_child(MenuWidgets.label(tr("Monsters")))
	_rows = VBoxContainer.new()
	add_child(_rows)
	_show([none_text()], [])


func _process(_delta: float) -> void:
	# Only while it's shown: the menu is open on the Character tab.
	if is_visible_in_tree():
		refresh()


## Shows the monsters as they are now; builds the rows anew only when that changed.
func refresh() -> void:
	var lines: Array[String] = []
	var ids: Array[String] = []
	var marks: Array[bool] = []
	if order.is_valid():
		ids = order.call()
		lines = _lines_of(ids)
		for short_id: String in ids:
			marks.append(KnotMark.waits(monster_by(short_id)))
	if lines.is_empty():
		lines.append(none_text())
	if lines != shown or ids != shown_ids or marks != marked:
		_show(lines, ids, marks)
	if not shown_ids.has(selected):
		selected = shown_ids[0] if not shown_ids.is_empty() else ""
	_show_details()


## What the list says while the player has no dominated monster.
static func none_text() -> String:
	return TranslationServer.tr("No dominated monsters yet")


## Shows the monster `short_id`'s stats in the detail pane, as a tap, a click or the focus does.
func select(short_id: String) -> void:
	selected = short_id
	_show_details()


func _show_details() -> void:
	var shown_monster: DominatedMonster = monster_by(selected)
	monster_shown.emit(shown_monster)
	if details == null:
		return
	var species: Species = null
	var ascension: SpeciesAscension = null
	var holds: int = 0
	var next: Species = null
	if shown_monster != null:
		species = _species.get(shown_monster.species)
		ascension = _ascensions.get(shown_monster.species)
	if ascension != null and materials.is_valid():
		var held: Dictionary[String, int] = materials.call()
		holds = held.get(ascension.material, 0)
	if ascension != null and knows.is_valid() and knows.call(ascension.into):
		next = _species.get(ascension.into)
	details.show_monster(shown_monster, species, _abilities, ascension, holds)
	details.show_next_form(next)


## The player's dominated monster `short_id`, or null: none without a profile.
func monster_by(short_id: String) -> DominatedMonster:
	return monster_of.call(short_id) if monster_of.is_valid() else null


## The short ids of the monsters the player carries, in their order: none without a profile.
func carried_ids() -> Array[String]:
	var ids: Array[String] = []
	if carried.is_valid():
		for short_id: String in carried.call():
			ids.append(short_id)
	return ids


## A line for each of the player's dominated monsters in `ids`, their order: the carried ones
## first, then the rest.
func _lines_of(ids: Array[String]) -> Array[String]:
	var lines: Array[String] = []
	var carrying: int = carried_ids().size()
	for place: int in ids.size():
		var described: String = _described(monster_by(ids[place]))
		if place == 0 and carrying > 0:
			lines.append(tr("Carried 1, companion: %s") % described)
		elif place < carrying:
			var parts: Dictionary[String, Variant] = { "place": place + 1, "monster": described }
			lines.append(tr("Carried {place}: {monster}").format(parts))
		else:
			lines.append(tr("Not carried: %s") % described)
	return lines


## Moves the monster `short_id` to `place` in the player's order, as its buttons and a drag do.
func move(short_id: String, place: int) -> void:
	if reorder.is_valid():
		reorder.call(short_id, place)
	refresh()


## `monster`'s species name and level, in words: every one in the order is there, as the save
## guarantees every carried one is (ProfileSave).
func _described(monster: DominatedMonster) -> String:
	var known: Species = _species.get(monster.species)
	var species_name: String = tr(known.name) if known != null else monster.species
	var parts: Dictionary[String, Variant] = { "species": species_name, "level": monster.level }
	return tr("{species}, level {level}").format(parts)


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
	var up: Callable = move.bind(short_id, place - 1)
	var down: Callable = move.bind(short_id, place + 1)
	row.add_child(MenuWidgets.icon_button(ResourcePacks.texture(UP_ICON), tr("Move up"), up))
	row.add_child(MenuWidgets.icon_button(ResourcePacks.texture(DOWN_ICON), tr("Move down"), down))
	return row


## A row's monster, dragged and dropped onto the row in `place`: it moves there.
func _dropped(data: Variant, place: int) -> void:
	var short_id: String = data
	move(short_id, place)


func _on_row_input(event: InputEvent, short_id: String) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		select(short_id)
