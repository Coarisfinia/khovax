class_name TileHarvested
extends RefCounted
## Event: a player harvested a tile by hand this tick (#696): it dropped its materials and turned
## into its depleted kind (a TileChanged event in the same tick says so). `loot` holds what each
## player in the instance got from it, by slot, as {item id: amount}.

## The entity id of the player who harvested it.
var harvester_id: int
var tile: Vector2i
## The tile's kind before it was harvested, as an id in TileKinds.
var kind: String
var loot: Dictionary[int, Dictionary]


func _init(
	by_id: int,
	on_tile: Vector2i,
	was_kind: String,
	rolled: Dictionary[int, Dictionary],
) -> void:
	harvester_id = by_id
	tile = on_tile
	kind = was_kind
	loot = rolled
