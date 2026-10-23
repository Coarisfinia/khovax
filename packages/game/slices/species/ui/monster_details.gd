class_name MonsterDetails
extends VBoxContainer
## The detail pane on the Character tab (#430): every stat of the dominated monster selected in the
## list beside it (DominatedMonstersList), in words: its species and level, its progress toward the
## next level (#1251), its types (each after
## its family's badge, TypeBadge), HP, strength and speed, its special attack and its two passives
## by name. It only reads what it's given.

const TITLE: String = "Details"
const NONE_TEXT: String = "No monster selected"
const UNKNOWN_TEXT: String = "Its species' stats can't be read"
const TYPES_HEADING: String = "Types:"
## Its progress toward the next level: what it has, what that level needs, and the level.
const PROGRESS_TEXT: String = "Progress: %d of %d to level %d"
## Which line names its types, shown with their family badges.
const TYPES_LINE: int = 2

## What the pane shows, one line each. Kept here so tests can read it.
var shown: Array[String] = []
var _lines: VBoxContainer


func _ready() -> void:
	add_child(GameMenu.label(TITLE))
	_lines = VBoxContainer.new()
	add_child(_lines)
	show_monster(null, null, {})


## Shows `monster`, of `species`, naming its abilities from `ability_names` (by id); with no
## monster, says none is selected.
func show_monster(
	monster: DominatedMonster,
	species: Species,
	ability_names: Dictionary[String, String],
) -> void:
	var lines: Array[String] = [NONE_TEXT]
	# A monster whose species the data lacks still shows, by its species id.
	if monster != null and species == null:
		lines = [
			"%s, level %d" % [monster.species, monster.level],
			_progress(monster),
			UNKNOWN_TEXT,
		]
	if monster != null and species != null:
		lines = [
			"%s, level %d" % [species.name, monster.level],
			_progress(monster),
			TYPES_HEADING + " " + ", ".join(species.types),
			"HP: %d" % species.hp,
			"Strength: %d" % species.strength,
			"Speed: %d" % species.speed,
			"Special: " + ability_names.get(species.special, species.special),
			"Passive for you: " + ability_names.get(species.player_passive, species.player_passive),
			"Own passive: " + ability_names.get(species.self_passive, species.self_passive),
		]
		# Its sight trait (#962), only for a species that has one.
		if species.sight > 0:
			lines.append("Sight: you see %d steps further while you carry it" % species.sight)
	if lines == shown:
		return
	shown = lines
	GameMenu.show_lines(_lines, lines)
	if monster != null and species != null:
		_badge_types(species.types)


## `monster`'s progress toward its next level, in words.
static func _progress(monster: DominatedMonster) -> String:
	var needed: int = DominatedMonster.progress_needed(monster.level)
	return PROGRESS_TEXT % [monster.progress, needed, monster.level + 1]


## Swaps the types' line for one that shows each type after its family's badge (#627).
func _badge_types(types: Array[String]) -> void:
	var plain: Node = _lines.get_child(TYPES_LINE)
	_lines.remove_child(plain)
	plain.queue_free()
	var badged: HBoxContainer = TypeBadge.row(TYPES_HEADING, types)
	_lines.add_child(badged)
	_lines.move_child(badged, TYPES_LINE)
