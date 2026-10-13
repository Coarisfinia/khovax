class_name Trail
extends RefCounted
## TrailFeature's data for one entity: every tile it has stood on or moved onto, as a set.

var tiles: Dictionary[Vector2i, bool] = {}


func _init(start: Vector2i) -> void:
	tiles[start] = true


## The trail's tiles, sorted, so their order never depends on how the trail was walked.
func sorted_tiles() -> Array[Vector2i]:
	var sorted: Array[Vector2i] = []
	sorted.assign(tiles.keys())
	sorted.sort()
	return sorted
