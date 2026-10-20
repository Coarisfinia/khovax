class_name TileChanged
extends RefCounted
## Event: a rule changed a tile's kind in place this tick (#530, GameState.change_tile), e.g.
## boulders cleared from a path. The views show the change calmly from it.

## The region the tile changed in: the driver hands views the events of an instance the player just
## left too, and only this tells them apart.
var region: Region
var tile: Vector2i
## The tile's kind before and after, as ids in TileKinds.
var was: String
var kind: String


func _init(in_region: Region, changed_tile: Vector2i, old_kind: String, new_kind: String) -> void:
	region = in_region
	tile = changed_tile
	was = old_kind
	kind = new_kind
