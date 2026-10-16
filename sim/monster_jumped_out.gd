class_name MonsterJumpedOut
extends RefCounted
## Event: a wild monster hidden in a tile that hides (#202) jumped out this tick, because a player
## came next to it. It stays on its tile.

var monster_id: int
var tile: Vector2i


func _init(by_id: int, on_tile: Vector2i) -> void:
	monster_id = by_id
	tile = on_tile
