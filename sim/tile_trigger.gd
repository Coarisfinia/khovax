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
## Every when and action the trigger feature knows.
const WHENS: Array[String] = [STEP]
const ACTIONS: Array[String] = [REVEAL]

var tile: Vector2i
var condition: String
var action: String
var amount: int


func _init(on_tile: Vector2i, fires_when: String, does: String, how_much: int) -> void:
	tile = on_tile
	condition = fires_when
	action = does
	amount = how_much


## The same trigger moved by `offset` and turned `turns` times by 60 degrees around the origin.
func moved(offset: Vector2i, turns: int = 0) -> TileTrigger:
	return TileTrigger.new(Hex.turn(tile, turns) + offset, condition, action, amount)
