class_name FogFeature
extends Feature
## Fog of war (#65): every tick, each player sees the tiles within their sight radius that a
## straight line reaches from where they stand without passing over rock. Water doesn't block
## sight, and the rock itself is seen. Visibility is simulation state (owner, #65): it's in the
## state hash, the same on every machine. An instance's scripted event can reveal an area (#177):
## its tiles count as seen before for every player, also in the state hash. How it is drawn
## (remembered tiles, allies' sight, monsters in fog) is FogView's.

## How far every player sees, in steps, until traits from captured monsters change it (#65).
const SIGHT_RADIUS: int = 5

## Each player's visible tiles, by slot, in a fixed order (Hex.disc's).
var visible: Dictionary[int, Array] = {}
## Tiles an event revealed to every player, sorted, each once (#177).
var revealed: Array[Vector2i] = []
## Where each player stood when their sight was last worked out, by slot.
var _seen_from: Dictionary[int, Vector2i] = {}


func id() -> int:
	return Features.FOG


func requires() -> Array[int]:
	var needed: Array[int] = [Features.MOVEMENT]
	return needed


func start(state: GameState) -> void:
	_update(state)


func step(state: GameState, _commands: Array[Command]) -> void:
	_update(state)


## A player sees from the moment they join, not only from the next tick on.
func entity_added(state: GameState, added: Entity) -> void:
	if added.slot != Entity.NO_SLOT:
		_update(state)


## A player who leaves loses their sight at once, so a slot rejoining never starts with it.
func entity_removed(state: GameState, _removed_id: int) -> void:
	_update(state)


## Reveals `tiles` of the region to every player: from now on they count as seen before. Only an
## instance's rules call it, inside a tick (#30), so every machine reveals the same.
func reveal(state: GameState, tiles: Array[Vector2i]) -> void:
	for tile: Vector2i in tiles:
		if state.region.has_tile(tile) and not revealed.has(tile):
			revealed.append(tile)
	revealed.sort()


## Whether the player in `slot` sees `tile`.
func sees(slot: int, tile: Vector2i) -> bool:
	return visible.has(slot) and visible[slot].has(tile)


func hash_values() -> Array[int]:
	var values: Array[int] = []
	for slot: int in GameState.MAX_PLAYERS:
		var tiles: Array = visible.get(slot, [])
		values.append(tiles.size())
		for tile: Vector2i in tiles:
			values.append(tile.x)
			values.append(tile.y)
	# Only once something is revealed, so the hash of every session without a reveal is unchanged.
	if not revealed.is_empty():
		values.append(revealed.size())
		for tile: Vector2i in revealed:
			values.append(tile.x)
			values.append(tile.y)
	return values


## Works out again the sight of every player who moved; players who left lose theirs.
func _update(state: GameState) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		var player: Entity = state.player(slot)
		if player == null:
			var _lost: bool = visible.erase(slot)
			var _forgot: bool = _seen_from.erase(slot)
		elif not _seen_from.has(slot) or _seen_from[slot] != player.tile:
			_seen_from[slot] = player.tile
			visible[slot] = sight(state.region, player.tile, SIGHT_RADIUS)


## The tiles of `region` within `radius` of `from` that a straight line reaches without passing
## over rock, in Hex.disc's order.
static func sight(region: Region, from: Vector2i, radius: int) -> Array[Vector2i]:
	var seen: Array[Vector2i] = []
	for tile: Vector2i in Hex.disc(radius, from):
		if region.has_tile(tile) and _clear(region, Hex.line(from, tile)):
			seen.append(tile)
	return seen


## Whether nothing between the line's ends blocks sight: no rock, and no gap in the region.
static func _clear(region: Region, path: Array[Vector2i]) -> bool:
	for i: int in range(1, path.size() - 1):
		var tile: Vector2i = path[i]
		if not region.has_tile(tile) or region.terrain[tile] == Region.BLOCKED:
			return false
	return true
