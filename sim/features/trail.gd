class_name Trail
extends RefCounted
## TrailFeature's data: the allies' one shared trail (#87), every tile a player has stood on or
## moved onto, each with the entity id of the player who colored it first. Who colored a ring's
## tiles is who contributed to it (#86).

## Each tile on the trail, with the entity id of the player who colored it first.
var tiles: Dictionary[Vector2i, int] = {}


## Colors `tile` for the player `by_id`, unless it's on the trail already; returns whether it's new.
func color(tile: Vector2i, by_id: int) -> bool:
	if tiles.has(tile):
		return false
	tiles[tile] = by_id
	return true


## The trail's tiles, sorted, so their order never depends on how the trail was walked.
func sorted_tiles() -> Array[Vector2i]:
	var sorted: Array[Vector2i] = []
	sorted.assign(tiles.keys())
	sorted.sort()
	return sorted
