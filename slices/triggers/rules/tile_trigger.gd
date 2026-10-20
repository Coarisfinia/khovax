class_name TileTrigger
extends RefCounted
## A trigger on a tile (#183): when something happens there, an action runs. Written in a region
## piece's legend in words, `<what it is>; <when> <action>` (TriggerPlacements), e.g. `a lookout;
## stepping here reveals within 8`, with these whens and actions: `stepping here`, `reveals within
## <n>`, `reaches the place <place id>` (#339: every tile of a place has it, e.g. `the beach;
## stepping here reaches the place beach`), and run by the trigger feature. The rules grow with this
## small vocabulary of whens and actions, never with every new kind of tile.

## When it fires: a player steps onto the tile.
const STEP: String = "step"
## What it does: reveals the region within `amount` of the tile to every player (#177).
const REVEAL: String = "reveal"
## What it does: the tile is part of the place `place` (#339), and a player stepping onto it from
## outside that place reaches it, every time and each player for themselves, for their quests.
const REACH: String = "reach"
## What a place's id looks like, like every content id.
const PLACE_ID: String = "^[a-z][a-z0-9_]*$"
## What separates what a trigger's tile is from its when and action in its legend meaning.
const SAID: String = "; "
## The whens and actions in words.
const WHENS: Dictionary[String, String] = { "stepping here ": STEP }
const ACTIONS: Dictionary[String, String] = {
	"reveals within ": REVEAL,
	"reaches the place ": REACH,
}

var tile: Vector2i
var condition: String
var action: String
## How far a reveal reaches; 0 for a place.
var amount: int
## The place a REACH trigger's tile is part of, or "".
var place: String


func _init(
	on_tile: Vector2i,
	fires_when: String,
	does: String,
	how_much: int,
	place_id: String = "",
) -> void:
	tile = on_tile
	condition = fires_when
	action = does
	amount = how_much
	place = place_id


## The trigger a legend `meaning` places on `on_tile`, or null when it places none or one that acts
## on nothing.
static func read(meaning: String, on_tile: Vector2i = Vector2i.ZERO) -> TileTrigger:
	var parts: PackedStringArray = meaning.split(SAID)
	if parts.size() != 2 or parts[0].strip_edges().is_empty():
		return null
	var when: String = ""
	var does: String = ""
	var said: String = ""
	for phrase: String in WHENS:
		var rest: String = parts[1].trim_prefix(phrase)
		for words: String in ACTIONS:
			if parts[1].begins_with(phrase) and rest.begins_with(words):
				when = WHENS[phrase]
				does = ACTIONS[words]
				said = rest.trim_prefix(words)
	if does == REACH and is_place_id(said):
		return TileTrigger.new(on_tile, when, REACH, 0, said)
	if not does.is_empty() and does != REACH and said.is_valid_int() and said.to_int() >= 1:
		return TileTrigger.new(on_tile, when, does, said.to_int())
	return null


## What the trigger's tile is, as its legend `meaning` says before its when (`forest`, `a
## lookout`).
static func what_it_is(meaning: String) -> String:
	return meaning.get_slice(SAID, 0)


## Every trigger `region`'s legend places, in the region file's reading order.
static func all_in(region: Region) -> Array[TileTrigger]:
	var triggers: Array[TileTrigger] = []
	var placed: Dictionary[Vector2i, String] = region.placed(TriggerPlacements.KIND)
	for spot: Vector2i in placed:
		triggers.append(read(placed[spot], spot))
	return triggers


## Whether `id` is a place's id.
static func is_place_id(id: String) -> bool:
	return RegEx.create_from_string(PLACE_ID).search(id) != null
