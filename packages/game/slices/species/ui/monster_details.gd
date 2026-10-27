class_name MonsterDetails
extends VBoxContainer
## The detail pane on the Character tab (#430): every stat of the dominated monster selected in the
## list beside it (DominatedMonstersList), in words: its species and level, its progress toward the
## next level (#1251), its types (each after
## its family's badge, TypeBadge), HP, strength and speed, its special attack and its two passives
## by name. A monster whose species ascends (#1235) shows into what, at which level and with which
## material, and an Ascend button that's pressable once it has reached that level and the player
## holds the material; after it ascends, a line says so. It only reads what it's given, and tells
## `ascend_chosen` when its button is pressed.

## The player pressed Ascend for the dominated monster `short_id`.
signal ascend_chosen(short_id: String)

const TITLE: String = "Details"
const NONE_TEXT: String = "No monster selected"
const UNKNOWN_TEXT: String = "Its species' stats can't be read"
const TYPES_HEADING: String = "Types:"
## Its progress toward the next level: what it has, what that level needs, and the level.
const PROGRESS_TEXT: String = "Progress: %d of %d to level %d"
## Which line names its types, shown with their family badges.
const TYPES_LINE: int = 2
## Its ascension (#1235): into which species and at which level, then with which material and how
## many of it the player holds. Two short lines, since the menu's lines trim.
const ASCENSION_TEXT: String = "Ascends into %s at level %d"
const MATERIAL_TEXT: String = "Given one %s: you hold %d"
const ASCEND_TEXT: String = "Ascend"
## Said once a monster has ascended: from which species into which.
const ASCENDED_TEXT: String = "%s ascended into %s!"

## What the pane shows, one line each. Kept here so tests can read it.
var shown: Array[String] = []
## The Ascend button, shown only for a monster whose species ascends.
var ascend_button: Button
## The line saying a monster just ascended, "" until one has. Kept here so tests can read it.
var notice: String = ""
var _lines: VBoxContainer
var _notice: Label
## The short id of the monster shown, whose ascension the button asks for.
var _short_id: String = ""


func _ready() -> void:
	add_child(GameMenu.label(TITLE))
	_lines = VBoxContainer.new()
	add_child(_lines)
	ascend_button = GameMenu.button(ASCEND_TEXT, func() -> void: ascend_chosen.emit(_short_id))
	add_child(ascend_button)
	_notice = GameMenu.label("")
	add_child(_notice)
	show_monster(null, null, {})


## Each ability's name as the player reads it, with its path mark in words (#471), by id: what
## `show_monster` names abilities from, and the development web its passive nodes (#1452).
static func all_ability_names() -> Dictionary[String, String]:
	var names: Dictionary[String, String] = {}
	var abilities: AbilityContent = AbilityContent.cached()
	for id: String in abilities.abilities:
		var ability: Ability = abilities.abilities[id]
		names[id] = PathMark.tagged(TextTags.shown(ability.name), ability.path)
	return names


## Shows `monster`, of `species`, naming its abilities from `ability_names` (by id), and its
## species' `ascension` with how many of its material the player `holds`; with no monster, says
## none is selected.
func show_monster(
	monster: DominatedMonster,
	species: Species,
	ability_names: Dictionary[String, String],
	ascension: SpeciesAscension = null,
	holds: int = 0,
) -> void:
	var short_id: String = monster.short_id if monster != null else ""
	if short_id != _short_id:
		tell_ascended("")
	_short_id = short_id
	var ascends: bool = monster != null and ascension != null
	ascend_button.visible = ascends
	ascend_button.disabled = not ascends or monster.level < ascension.level or holds < 1
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
		if ascends:
			var given: String = ascension.material.replace("_", " ")
			var grown: Species = SpeciesContent.cached().species.get(ascension.into)
			var into: String = grown.name if grown != null else ascension.into
			lines.append(ASCENSION_TEXT % [into, ascension.level])
			lines.append(MATERIAL_TEXT % [given, holds])
	if lines == shown:
		return
	shown = lines
	GameMenu.show_lines(_lines, lines)
	if monster != null and species != null:
		_badge_types(species.types)


## Says `text` below the pane, like that the monster shown just ascended, or nothing for "".
func tell_ascended(text: String) -> void:
	notice = text
	if _notice == null:
		return
	_notice.text = text
	_notice.visible = not text.is_empty()


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
