class_name QuestStanding
extends RefCounted
## How finishing a quest moves the player's standing with a faction (#532): the faction and the
## change, up or down, applied to their profile's Standings when the quest finishes.

## A standing entry's fields, as the quest schema (slices/quests/data/quests.schema.json) allows
## them.
const FIELDS: Array[String] = ["faction", "change"]
## The largest change either way: the whole scale, from one end to the other.
const MAX_CHANGE: int = Standings.HIGHEST - Standings.LOWEST

## The faction's id; QuestContent checks that it exists.
var faction: String = ""
## How far the standing moves: up when positive, down when negative, never 0.
var change: int = 0
## Why the entry couldn't be read, or "" when it could.
var problem: String = ""


## A standing change read from a quest file's `standing` entry. Its `problem` says what's wrong.
static func parse(entry: Variant) -> QuestStanding:
	var standing: QuestStanding = QuestStanding.new()
	if not entry is Dictionary:
		standing.problem = "it isn't an object"
		return standing
	var data: Dictionary = entry
	standing.faction = Content.text_of(data.get("faction"))
	standing.problem = Content.unknown_field(data, FIELDS)
	if not standing.problem.is_empty():
		return standing
	if not Content.is_id(standing.faction):
		standing.problem = "its faction must be an id, lowercase words joined by underscores"
		return standing
	var raw: Variant = data.get("change")
	var number: float = raw if raw is int or raw is float else 0.0
	# Read through its size, so a fraction, anything but a number, or 0 reads as no change.
	var size: int = Content.amount(absf(number))
	standing.change = size if number > 0.0 else -size
	if size == 0 or size > MAX_CHANGE:
		standing.problem = "its change is a whole number from -%d to %d, never 0" % [
			MAX_CHANGE,
			MAX_CHANGE,
		]
	return standing
