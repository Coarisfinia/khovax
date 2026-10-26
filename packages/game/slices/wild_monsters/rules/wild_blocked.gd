class_name WildBlocked
extends RefCounted
## The tiles a wild monster may not step onto of its own accord (WildGround.blocked): the trail, so
## it never walks into a ring, and every tile something stands on. It reads the trail where it is
## instead of copying it, since the trail only grows while the players walk and the monsters ask
## for their ground every time one of them chases or forages (#1311).

## The trail's tiles, as the trail feature keeps them: read, never written.
var _trail: Dictionary
## The tiles something stands on, and those `add` took since.
var _taken: Dictionary[Vector2i, bool] = {}


func _init(trail: Dictionary, taken: Dictionary[Vector2i, bool]) -> void:
	_trail = trail
	_taken = taken


func has(tile: Vector2i) -> bool:
	return _taken.has(tile) or _trail.has(tile)


## Marks `tile` taken: a monster stepped onto it this tick.
func add(tile: Vector2i) -> void:
	_taken[tile] = true
