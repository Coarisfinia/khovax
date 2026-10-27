class_name BestiaryEntry
extends VBoxContainer
## A species' bestiary entry on its codex page (#1173), showing only what this machine's player has
## learned about it (Bestiary): once they've seen one, its picture (SpeciesPicture, #1190), and
## before that nothing in its place, not even a silhouette, which would give its shape away; once
## they've met one in a fight, its types (each after its family's badge, TypeBadge), its special
## attack and two passives by name, and the instances they've come across it in; once they've
## dominated one, its lore. What's still to learn is said in words, so the player knows how to learn
## it. The instances a realm draws are links in the habitat line (NameLinks, #1175): selecting one
## raises `name_selected`, which opens its place's page. They need no `name_shown`: the player met
## each when they entered it (#1209), which is where they came across the species.

## A place in the habitat line was selected (NameLinks): TextTags.PLACE and its id.
signal name_selected(kind: String, id: String)

const NOT_SEEN_TEXT: String = "You haven't seen one yet."
const NOT_MET_TEXT: String = "Fight one to learn its types, abilities and haunts."
const NOT_KNOWN_TEXT: String = "Dominate one to learn its lore."
const TYPES_HEADING: String = "Types:"
const SPECIAL_TEXT: String = "Special: %s"
const PLAYER_PASSIVE_TEXT: String = "Passive for you: %s"
const SELF_PASSIVE_TEXT: String = "Own passive: %s"
const HABITAT_TEXT: String = "Found in: %s"

## What the entry shows, one line each, its types as their heading and names: kept here so tests
## can read it.
var shown: Array[String] = []
## The species' picture, or null while the player hasn't seen one: kept here so tests can read it.
var picture: SpeciesPicture
## The habitat line, or null while the entry shows none: kept here so tests can read it.
var habitat_line: NameLinks


## Shows what `bestiary` (null for nothing learned) knows about `species`.
func show_species(species: Species, bestiary: Bestiary) -> void:
	for old: Node in get_children():
		remove_child(old)
		old.queue_free()
	shown.clear()
	picture = null
	habitat_line = null
	var level: int = bestiary.level_of(species.id) if bestiary != null else 0
	if level < Bestiary.SEEN:
		_add_line(NOT_SEEN_TEXT)
	else:
		picture = SpeciesPicture.new(species.id)
		add_child(picture)
	if level < Bestiary.MET:
		_add_line(NOT_MET_TEXT)
	else:
		_show_met(species, bestiary.habitat_of(species.id))
	_add_line(species.codex_entry() if level >= Bestiary.KNOWN else NOT_KNOWN_TEXT)


## What meeting `species` teaches: its types, its abilities and where it was come across.
func _show_met(species: Species, habitat: Array[String]) -> void:
	add_child(TypeBadge.row(TYPES_HEADING, species.types))
	shown.append(TYPES_HEADING + " " + ", ".join(species.types))
	_add_line(SPECIAL_TEXT % _ability_name(species.special))
	_add_line(PLAYER_PASSIVE_TEXT % _ability_name(species.player_passive))
	_add_line(SELF_PASSIVE_TEXT % _ability_name(species.self_passive))
	var places: Array[String] = []
	for where: String in habitat:
		# Only a realm's instance has a place page (TextTags.PLACE); the playground has none.
		var tagged: bool = Realms.holding(where) != null
		places.append(TextTags.tag(TextTags.PLACE, where) if tagged else Realms.name_of(where))
	if not places.is_empty():
		_add_habitat(HABITAT_TEXT % ", ".join(places))


## Adds the habitat line `tagged`, a text with text tags, its places as links.
func _add_habitat(tagged: String) -> void:
	habitat_line = NameLinks.new()
	var _selected: int = habitat_line.name_selected.connect(name_selected.emit)
	add_child(habitat_line)
	habitat_line.show_tagged(tagged)
	shown.append(TextTags.shown(tagged))


func _add_line(text: String) -> void:
	var line: Label = Label.new()
	line.text = text
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(line)
	shown.append(text)


## The name the player reads for the ability `id`, or its id while the abilities can't be read.
static func _ability_name(id: String) -> String:
	var ability: Ability = AbilityContent.cached().abilities.get(id)
	return TextTags.shown(ability.name) if ability != null else id
