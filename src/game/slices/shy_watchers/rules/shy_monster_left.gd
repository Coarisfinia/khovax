class_name ShyMonsterLeft
extends RefCounted
## Event: a shy wild monster (#2416, ShyWatcherFeature) hid when a player came near, stepped away
## out of sight at its pace, and left the region for good in this world. Its entity is already gone.

var monster_id: int
## The region spot it originally watched from, which it never returns to in this world.
var spot: Vector2i
## The tile it stood on when it left the region.
var tile: Vector2i
## Its species id and its short id (ShortId, #700).
var species: String
var short_id: String


func _init(
	left_id: int,
	from_spot: Vector2i,
	last_tile: Vector2i,
	species_id: String,
	short: String,
) -> void:
	monster_id = left_id
	spot = from_spot
	tile = last_tile
	species = species_id
	short_id = short
