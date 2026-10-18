class_name TileChanged
extends RefCounted
## Event: a rule changed a tile's kind in place this tick (#530, GameState.change_tile), e.g.
## boulders cleared from a path. The views show the change calmly from it.

var tile: Vector2i
## The tile's kind before and after, as numbers in TileKinds.
var was: int
var kind: int


func _init(changed_tile: Vector2i, old_kind: int, new_kind: int) -> void:
	tile = changed_tile
	was = old_kind
	kind = new_kind
