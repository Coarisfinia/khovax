class_name TileTrigger
extends RefCounted
## A trigger on a tile (#183): when something happens there, an action runs. Written in a region
## piece's legend in words (`a lookout; stepping here reveals within 8`) and run by the trigger
## feature. The rules grow with this small vocabulary of whens and actions, never with every new
## kind of tile.

## When it fires: a player steps onto the tile.
const STEP: String = "step"
## What it does: reveals the region within `amount` of the tile to every player (#177).
const REVEAL: String = "reveal"
## What it does: the tile is part of the place `place` (#339), and a player stepping onto it from
## outside that place reaches it, every time and each player for themselves, for their quests.
const REACH: String = "reach"
## Every when and action the trigger feature knows.
const WHENS: Array[String] = [STEP]
const ACTIONS: Array[String] = [REVEAL, REACH]
## What a place's id looks like, like every content id.
const PLACE_ID: String = "^[a-z][a-z0-9_]*$"

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


## The same trigger moved by `offset` and turned `turns` times by 60 degrees around the origin.
func moved(offset: Vector2i, turns: int = 0) -> TileTrigger:
	return TileTrigger.new(Hex.turn(tile, turns) + offset, condition, action, amount, place)


## Whether `id` is a place's id.
static func is_place_id(id: String) -> bool:
	return RegEx.create_from_string(PLACE_ID).search(id) != null
