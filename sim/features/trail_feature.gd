class_name TrailFeature
extends Feature
## The trail: every tile the player has stood on or moved onto, as a set. Rings are drawn with it.
## It grows from PlayerMoved events, so it comes after movement in an instance's order. Walking
## over it again changes nothing yet.

var tiles: Dictionary[Vector2i, bool] = {}


func id() -> int:
	return Features.TRAIL


func requires() -> Array[int]:
	var needed: Array[int] = [Features.MOVEMENT]
	return needed


func start(state: GameState) -> void:
	tiles[state.player_tile] = true


func step(state: GameState, _commands: Array[Command]) -> void:
	for event: RefCounted in state.events:
		var moved: PlayerMoved = event as PlayerMoved
		if moved != null:
			tiles[moved.to] = true


## The trail's tiles, sorted, so their order never depends on how the trail was walked.
func sorted_tiles() -> Array[Vector2i]:
	var sorted: Array[Vector2i] = []
	sorted.assign(tiles.keys())
	sorted.sort()
	return sorted


func hash_values() -> Array[int]:
	var values: Array[int] = [tiles.size()]
	for tile: Vector2i in sorted_tiles():
		values.append(tile.x)
		values.append(tile.y)
	return values
