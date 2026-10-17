class_name DominatedMonstersList
extends VBoxContainer
## The player's dominated monsters on the menu's Character tab (#400): every one in their profile,
## by its species' name and its level. The three they carry come first, in the order they come in
## (#53), the first of them their companion (#338); each line says in words whether it's carried
## and where, never by color alone (#68). It only reads the profile, and keeps up with it while
## shown. Choosing the carried three belongs to the player's base (#50).

const TITLE: String = "Monsters"
const NONE_TEXT: String = "No dominated monsters yet"
const COMPANION_TEXT: String = "Carried 1, companion: "
const CARRIED_TEXT: String = "Carried %d: "
const RESTING_TEXT: String = "Not carried: "

## Whose monsters are shown: this machine's player's profile.
var holder: ProfileHolder
## What the list shows, one line per monster. Kept here so tests can read it.
var shown: Array[String] = []
## Each species' name, by id; a species missing from the data shows its id.
var _names: Dictionary[String, String] = {}
var _rows: VBoxContainer


func _ready() -> void:
	var species: Content = SpeciesContent.load_species()
	if not species.problem.is_empty():
		push_warning("the species can't be read, so monsters show their ids: " + species.problem)
	for id: String in species.species:
		_names[id] = species.species[id].name
	add_child(GameMenu.label(TITLE))
	_rows = VBoxContainer.new()
	add_child(_rows)
	_show([NONE_TEXT])


func _process(_delta: float) -> void:
	# Only while it's shown: the menu is open on the Character tab.
	if is_visible_in_tree():
		refresh()


## Shows the monsters as they are now; builds the rows anew only when that changed.
func refresh() -> void:
	var lines: Array[String] = []
	if holder != null and holder.keeper != null:
		lines = _lines_of(holder.keeper.profile)
	if lines.is_empty():
		lines.append(NONE_TEXT)
	if lines != shown:
		_show(lines)


## A line for each of `profile`'s dominated monsters: the carried ones first, in their order, then
## the rest in the order dominated.
func _lines_of(profile: Profile) -> Array[String]:
	var lines: Array[String] = []
	for place: int in profile.carried.size():
		var prefix: String = COMPANION_TEXT if place == 0 else CARRIED_TEXT % (place + 1)
		lines.append(prefix + _described(_monster(profile, profile.carried[place])))
	for monster: DominatedMonster in profile.dominated_monsters:
		if not profile.carried.has(monster.id):
			lines.append(RESTING_TEXT + _described(monster))
	return lines


## The dominated monster with id `monster_id` in `profile`; the save guarantees every carried one
## is there (ProfileSave).
static func _monster(profile: Profile, monster_id: int) -> DominatedMonster:
	for monster: DominatedMonster in profile.dominated_monsters:
		if monster.id == monster_id:
			return monster
	return DominatedMonster.new(monster_id)


## `monster`'s species name and level, in words.
func _described(monster: DominatedMonster) -> String:
	return "%s, level %d" % [_names.get(monster.species, monster.species), monster.level]


## Builds a row for each of `lines`.
func _show(lines: Array[String]) -> void:
	shown = lines
	for row: Node in _rows.get_children():
		row.queue_free()
	for line: String in lines:
		_rows.add_child(GameMenu.label(line))
