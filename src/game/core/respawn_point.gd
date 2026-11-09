class_name RespawnPoint
extends RefCounted
## Where a player goes back to when they're sent to the spawn (#1890): a tile in an instance, kept
## in
## their world store, so it lasts with the world. A rule sets it (a waystone the player activated,
## in the waystones slice); the world reads it when it moves a player sent to the spawn
## (WorldTravel), and lands them beside it. Without one, or once its tile no longer holds the kind
## it
## was set on (the instance was arranged again), they go to the world's spawn, as before. The core
## owns the entry, so it reads it without knowing the rule that set it.

## The entry's key in a player's world store: saved and hashed, so never changed once it shipped.
const ENTRY: String = "respawn_point"


## Makes `tile` in the instance `instance_name`, whose state is `state`, the respawn point of the
## player in `slot`, inside a tick while they're there. Returns whether it wasn't already.
static func set_to(state: GameState, slot: int, instance_name: String, tile: Vector2i) -> bool:
	var wanted: Dictionary = {
		"instance": instance_name,
		"q": tile.x,
		"r": tile.y,
		"kind": state.region.terrain.get(tile, ""),
	}
	var entry: Dictionary = state.store(slot, ENTRY)
	if entry == wanted:
		return false
	entry.merge(wanted, true)
	return true


## The instance and the tile of a player's respawn point, as read from `entry`, their stored entry:
## `[instance, tile]`, or empty for none.
static func of(entry: Dictionary) -> Array:
	var instance_name: Variant = entry.get("instance")
	var q: Variant = entry.get("q")
	var r: Variant = entry.get("r")
	if not instance_name is String or not q is int or not r is int:
		return []
	var tile_q: int = q
	var tile_r: int = r
	return [instance_name, Vector2i(tile_q, tile_r)]


## Whether the respawn point `entry` was set on still holds the kind it was set on in `region`.
static func still_there(entry: Dictionary, region: Region, tile: Vector2i) -> bool:
	var kind: Variant = entry.get("kind")
	return kind is String and region.terrain.get(tile, "") == kind
