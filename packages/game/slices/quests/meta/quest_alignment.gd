class_name QuestAlignment
extends RefCounted
## A story choice that enforces the player's alignment with a faction (#1326, #1310), such as
## handing in an artifact: finishing the quest sets their standing with it to at least, or at most,
## a rank, rather than moving it by a change. A standing already within those bounds stays where it
## is. Raising a standing to its floor gains rank like any gain, so it costs half that with the
## faction's enemies (Standings.align).

## Where an alignment entry is in the quest schema (QuestDefinition.SCHEMA), which says the fields
## it may have.
const POINTER: String = "/properties/alignment/items"

## The faction's id; QuestContent checks that it exists.
var faction: String = ""
## The lowest standing it leaves the player at: Standings.LOWEST when the entry sets no floor.
var at_least: int = Standings.LOWEST
## The highest standing it leaves the player at: Standings.HIGHEST when the entry sets no ceiling.
var at_most: int = Standings.HIGHEST
## Why the entry couldn't be read, or "" when it could.
var problem: String = ""


## An alignment read from one entry of a quest file's `alignment` list. Its `problem` says what's
## wrong.
static func parse(entry: Variant) -> QuestAlignment:
	var alignment: QuestAlignment = QuestAlignment.new()
	if not entry is Dictionary:
		alignment.problem = "it isn't an object"
		return alignment
	var data: Dictionary = entry
	alignment.faction = Content.text_of(data.get("faction"))
	alignment.problem = Content.unknown_field(
		data,
		SchemaFields.at(QuestDefinition.SCHEMA, POINTER),
	)
	if not alignment.problem.is_empty():
		return alignment
	if not Content.is_id(alignment.faction):
		alignment.problem = "its faction must be an id, lowercase words joined by underscores"
		return alignment
	if not data.has("at_least") and not data.has("at_most"):
		alignment.problem = "it sets neither at_least nor at_most"
		return alignment
	# A fraction, anything but a number, or a rank off the scale reads as LOWEST - 1, refused below.
	var off: int = Standings.LOWEST - 1
	if data.has("at_least"):
		alignment.at_least = JsonNumbers.whole(
			data.get("at_least"),
			Standings.LOWEST,
			Standings.HIGHEST,
			off,
		)
	if data.has("at_most"):
		alignment.at_most = JsonNumbers.whole(
			data.get("at_most"),
			Standings.LOWEST,
			Standings.HIGHEST,
			off,
		)
	if alignment.at_least == off or alignment.at_most == off:
		alignment.problem = "its ranks are whole numbers from %d to %d" % [
			Standings.LOWEST,
			Standings.HIGHEST,
		]
	elif alignment.at_least > alignment.at_most:
		alignment.problem = "its at_least is above its at_most"
	return alignment


## The standing it leaves the player at, from `standing`: held between its floor and its ceiling.
func enforced(standing: int) -> int:
	return clampi(standing, at_least, at_most)
