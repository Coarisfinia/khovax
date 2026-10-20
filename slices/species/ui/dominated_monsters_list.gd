class_name DominatedMonstersList
extends VBoxContainer
## The player's dominated monsters on the menu's Character tab (#400): every one in their profile,
## by its species' name and its level. The three they carry come first, in the order they come in
## (#53), the first of them their companion (#338); each line says in words whether it's carried
## and where, never by color alone (#68). It keeps up with the profile while shown. The player
## orders them (#430): a row dragged onto another takes its place, and each row's up and down
## buttons move it one place, which a controller reaches too (#438). The first three are carried.

const TITLE: String = "Monsters"
const NONE_TEXT: String = "No dominated monsters yet"
const COMPANION_TEXT: String = "Carried 1, companion: "
const CARRIED_TEXT: String = "Carried %d: "
const RESTING_TEXT: String = "Not carried: "
## The buttons that move a monster one place up or down in the order.
const UP_TEXT: String = "▲"
const DOWN_TEXT: String = "▼"

## Whose monsters are shown: this machine's player's profile.
var holder: ProfileHolder
## What the list shows, one line per monster. Kept here so tests can read it.
var shown: Array[String] = []
## The monster each row shows, by entity id, in the rows' order.
var shown_ids: Array[int] = []
## The monster whose stats the detail pane shows, by entity id: the first one until the player
## taps, clicks or moves the focus onto another (#430).
var selected: int = 0
## The pane that shows the selected monster's stats, if the tab has one.
var details: MonsterDetails
## Each species' data and each ability's name with its path mark in words (#471), by id; a species
## missing from the data shows its id.
var _species: Dictionary[String, Species] = {}
var _abilities: Dictionary[String, String] = {}
var _rows: VBoxContainer


func _ready() -> void:
	var species: SpeciesContent = SpeciesContent.load_species()
	if not species.problem.is_empty():
		push_warning("the species can't be read, so monsters show their ids: " + species.problem)
	_species = species.species
	var abilities: AbilityContent = AbilityContent.load_abilities()
	for id: String in abilities.abilities:
		var ability: Ability = abilities.abilities[id]
		_abilities[id] = PathMark.tagged(TextTags.shown(ability.name), ability.path)
	add_child(GameMenu.label(TITLE))
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
	var ids: Array[int] = []
	if holder != null and holder.keeper != null:
		ids = holder.keeper.profile.order()
		lines = _lines_of(holder.keeper.profile, ids)
	if lines.is_empty():
		lines.append(NONE_TEXT)
	if lines != shown or ids != shown_ids:
		_show(lines, ids)
	if not shown_ids.has(selected):
		selected = shown_ids[0] if not shown_ids.is_empty() else 0
	_show_details()


## Shows the monster `monster_id`'s stats in the detail pane, as a tap, a click or the focus does.
func select(monster_id: int) -> void:
	selected = monster_id
	_show_details()


func _show_details() -> void:
	if details == null:
		return
	var monster: DominatedMonster = null
	if selected != 0 and holder != null and holder.keeper != null:
		monster = _monster(holder.keeper.profile, selected)
	var species: Species = null
	if monster != null:
		species = _species.get(monster.species)
	details.show_monster(monster, species, _abilities)


## A line for each of `profile`'s dominated monsters in `ids`, the player's order: the carried
## ones first, then the rest.
func _lines_of(profile: Profile, ids: Array[int]) -> Array[String]:
	var lines: Array[String] = []
	for place: int in ids.size():
		var prefix: String = RESTING_TEXT
		if place < profile.carried.size():
			prefix = COMPANION_TEXT if place == 0 else CARRIED_TEXT % (place + 1)
		lines.append(prefix + _described(_monster(profile, ids[place])))
	return lines


## Moves the monster `monster_id` to `place` in the player's order, as its buttons and a drag do.
func move(monster_id: int, place: int) -> void:
	if holder != null:
		holder.move_monster(monster_id, place)
	refresh()


## The dominated monster with id `monster_id` in `profile`; the save guarantees every carried one
## is there (ProfileSave).
static func _monster(profile: Profile, monster_id: int) -> DominatedMonster:
	for monster: DominatedMonster in profile.dominated_monsters:
		if monster.id == monster_id:
			return monster
	return DominatedMonster.new(monster_id)


## `monster`'s species name and level, in words.
func _described(monster: DominatedMonster) -> String:
	var known: Species = _species.get(monster.species)
	return "%s, level %d" % [known.name if known != null else monster.species, monster.level]


## Builds a row for each of `lines`, showing the monster of the same place in `ids`, if any.
func _show(lines: Array[String], ids: Array[int]) -> void:
	shown = lines
	shown_ids = ids
	# Out of the list at once, so its buttons and places are only ever the current ones.
	for row: Node in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	for place: int in lines.size():
		_rows.add_child(_row(lines[place], ids[place] if place < ids.size() else 0, place))


## A monster's row: its line, which can be dragged onto another row, and its up and down buttons.
## Without a monster (`monster_id` 0), the line alone.
func _row(line: String, monster_id: int, place: int) -> Control:
	var text: Label = GameMenu.label(line)
	if monster_id == 0:
		return text
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_STOP
	# A tap or a click shows it in the detail pane, and so does a controller's focus (#438).
	text.focus_mode = Control.FOCUS_ALL
	var _focused: int = text.focus_entered.connect(select.bind(monster_id))
	var _tapped: int = text.gui_input.connect(_on_row_input.bind(monster_id))
	text.set_drag_forwarding(
		func(_at: Vector2) -> Variant: return monster_id,
		func(_at: Vector2, data: Variant) -> bool: return data is int,
		func(_at: Vector2, data: Variant) -> void: _dropped(data, place),
	)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_child(text)
	row.add_child(GameMenu.button(UP_TEXT, move.bind(monster_id, place - 1)))
	row.add_child(GameMenu.button(DOWN_TEXT, move.bind(monster_id, place + 1)))
	return row


## A row's monster, dragged and dropped onto the row in `place`: it moves there.
func _dropped(data: Variant, place: int) -> void:
	var monster_id: int = data
	move(monster_id, place)


func _on_row_input(event: InputEvent, monster_id: int) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		select(monster_id)
