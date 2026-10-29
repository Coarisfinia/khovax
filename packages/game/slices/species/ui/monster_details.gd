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

## Which line names its types, shown with their family badges.
const TYPES_LINE: int = 2

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
	add_child(MenuWidgets.label(tr("Details")))
	_lines = VBoxContainer.new()
	add_child(_lines)
	ascend_button = MenuWidgets.button(tr("Ascend"), func() -> void: ascend_chosen.emit(_short_id))
	add_child(ascend_button)
	_notice = MenuWidgets.label("")
	add_child(_notice)
	show_monster(null, null, {})


## Each ability's name as the player reads it, with its path mark in words (#471), by id: what
## `show_monster` names abilities from, and the development web its passive nodes (#1452).
static func all_ability_names() -> Dictionary[String, String]:
	var names: Dictionary[String, String] = {}
	var abilities: AbilityContent = AbilityContent.cached()
	for id: String in abilities.abilities:
		var ability: Ability = abilities.abilities[id]
		var shown_name: String = TextTags.shown(TranslationServer.tr(ability.name))
		names[id] = PathMark.tagged(shown_name, ability.path)
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
	var lines: Array[String] = [tr("No monster selected")]
	# A monster whose species the data lacks still shows, by its species id.
	if monster != null and species == null:
		lines = [
			tr("%s, level %d") % [monster.species, monster.level],
			_progress(monster),
			tr("Its species' stats can't be read"),
		]
	if monster != null and species != null:
		var player_passive: String = species.player_passive
		lines = [
			tr("%s, level %d") % [tr(species.name), monster.level],
			_progress(monster),
			_types_heading() + " " + ", ".join(species.types),
			tr("HP: %d") % species.hp,
			tr("Strength: %d") % species.strength,
			tr("Speed: %d") % species.speed,
			tr("Special: %s") % ability_names.get(species.special, species.special),
			tr("Passive for you: %s") % ability_names.get(player_passive, player_passive),
			tr("Own passive: %s") % ability_names.get(species.self_passive, species.self_passive),
		]
		# Its sight trait (#962), only for a species that has one.
		if species.sight > 0:
			lines.append(tr("Sight: you see %d steps further while you carry it") % species.sight)
		if ascends:
			var given: String = ascension.material.replace("_", " ")
			var grown: Species = SpeciesContent.cached().species.get(ascension.into)
			var into: String = tr(grown.name) if grown != null else ascension.into
			lines.append(ascension_text(into, ascension.level))
			lines.append(material_text(given, holds))
	if lines == shown:
		return
	shown = lines
	MenuWidgets.show_lines(_lines, lines)
	if monster != null and species != null:
		_badge_types(species.types)


## Its ascension (#1235): into which species, `into`, and at which `level`. With material_text, two
## short lines, since the menu's lines trim.
static func ascension_text(into: String, level: int) -> String:
	return TranslationServer.tr("Ascends into %s at level %d") % [into, level]


## Its ascension's material, `given`, and how many of it the player `holds`.
static func material_text(given: String, holds: int) -> String:
	return TranslationServer.tr("Given one %s: you hold %d") % [given, holds]


## Said once a monster has ascended: from which species, `from`, into which, `into`.
static func ascended_text(from: String, into: String) -> String:
	return TranslationServer.tr("%s ascended into %s!") % [from, into]


## Says `text` below the pane, like that the monster shown just ascended, or nothing for "".
func tell_ascended(text: String) -> void:
	notice = text
	if _notice == null:
		return
	_notice.text = text
	_notice.visible = not text.is_empty()


## `monster`'s progress toward its next level, in words: what it has, what that level needs, and
## the level.
func _progress(monster: DominatedMonster) -> String:
	var needed: int = DominatedMonster.progress_needed(monster.level)
	return tr("Progress: %d of %d to level %d") % [monster.progress, needed, monster.level + 1]


## The heading before its types.
func _types_heading() -> String:
	return tr("Types:")


## Swaps the types' line for one that shows each type after its family's badge (#627).
func _badge_types(types: Array[String]) -> void:
	var plain: Node = _lines.get_child(TYPES_LINE)
	_lines.remove_child(plain)
	plain.queue_free()
	var badged: HBoxContainer = TypeBadge.row(_types_heading(), types)
	_lines.add_child(badged)
	_lines.move_child(badged, TYPES_LINE)
