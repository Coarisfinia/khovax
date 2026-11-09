class_name FogFeature
extends Feature
## Fog of war (#65): every tick, each player sees the tiles within their sight radius that a
## straight line reaches from where they stand without passing over rock. Water doesn't block
## sight, and the rock itself is seen. Visibility is simulation state (owner, #65): it's in the
## state hash, the same on every machine. An instance's scripted event can reveal an area (#177):
## its tiles count as seen before for every player, also in the state hash. How it is drawn
## (remembered tiles, allies' sight, monsters in fog) is FogView's. Sight traits from a player's
## carried monsters see further (#962): a later rule widens their sight (`widen`).

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "fog"
## How far every player sees, in steps, unless sight traits widen it (#962).
const SIGHT_RADIUS: int = 5
## The most steps a sight trait widens a player's sight by.
const MOST_WIDER: int = 5

## Each radius's lines, as _lines_within works them out, shared by every instance.
static var _lines: Dictionary[int, Array] = {}

## Each player's visible tiles, by slot, in a fixed order (Hex.disc's).
var visible: Dictionary[int, Array] = {}
## Tiles an event revealed to every player, sorted, each once (#177).
var revealed: Array[Vector2i] = []
## Where each player stood when their sight was last worked out, by slot.
var _seen_from: Dictionary[int, Vector2i] = {}
## How many steps beyond SIGHT_RADIUS each player sees, by slot, for those who see further (#962).
var _wider: Dictionary[int, int] = {}


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [MovementFeature.ID]
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


## A tile changed in place (#530) may block sight or stop blocking it: everyone's is worked out
## again at once.
func tile_changed(state: GameState, _tile: Vector2i) -> void:
	_see_again(state)


## The ground next door changed (#538): a tile there may block sight across the seam or stop
## blocking it, so everyone's is worked out again at once.
func next_door_changed(state: GameState) -> void:
	_see_again(state)


## Works out everyone's sight again, wherever they stand.
func _see_again(state: GameState) -> void:
	_seen_from.clear()
	_update(state)


## Reveals `tiles` of the region to every player: from now on they count as seen before. Only an
## instance's rules call it, inside a tick (#30), so every machine reveals the same.
func reveal(state: GameState, tiles: Array[Vector2i]) -> void:
	for tile: Vector2i in tiles:
		if state.region.has_tile(tile) and not revealed.has(tile):
			revealed.append(tile)
	revealed.sort()


## Widens the sight of the player in `slot` to `steps` beyond SIGHT_RADIUS (0 for none, #962).
## Only rules call it, inside a tick (#30): their sight is worked out again at once when it changes,
## and the fog's view eases it open or closed like any other change.
func widen(state: GameState, slot: int, steps: int) -> void:
	var wider: int = clampi(steps, 0, MOST_WIDER)
	if state.player(slot) == null or wider == radius_of(slot) - SIGHT_RADIUS:
		return
	if wider == 0:
		var _narrowed: bool = _wider.erase(slot)
	else:
		_wider[slot] = wider
	var _forgot: bool = _seen_from.erase(slot)
	_update(state)


## How far the player in `slot` sees, in steps.
func radius_of(slot: int) -> int:
	var wider: int = _wider.get(slot, 0)
	return SIGHT_RADIUS + wider


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
	# Only for a player who sees further, so the hash of every session without one is unchanged.
	if not _wider.is_empty():
		values.append(_wider.size())
		for slot: int in GameState.MAX_PLAYERS:
			if _wider.has(slot):
				values.append_array([slot, _wider[slot]])
	return values


## Where each player's sight was worked out from and how much further they see, by slot, and the
## revealed tiles. The visible tiles follow from those, so they're worked out again on loading.
func save_values() -> Dictionary:
	var seen: Array[int] = []
	var wider: Array[int] = []
	for slot: int in GameState.MAX_PLAYERS:
		if _seen_from.has(slot):
			seen.append_array([slot, _seen_from[slot].x, _seen_from[slot].y])
		if _wider.has(slot):
			wider.append_array([slot, _wider[slot]])
	return { "seen_from": seen, "wider": wider, "revealed": DataReader.flat(revealed) }


func load_values(state: GameState, values: DataReader) -> void:
	visible.clear()
	_seen_from.clear()
	_wider.clear()
	var wider: Array[int] = values.wholes("wider", 0, DataReader.MOST)
	if wider.size() % 2 != 0:
		values.fail("a player's wider sight is cut off")
		return
	for i: int in range(0, wider.size(), 2):
		var slot: int = wider[i]
		if state.player(slot) == null or _wider.has(slot) or wider[i + 1] > MOST_WIDER:
			values.fail("slot %d's wider sight isn't one player's, up to %d" % [slot, MOST_WIDER])
			return
		if wider[i + 1] > 0:
			_wider[slot] = wider[i + 1]
	var seen: Array[int] = values.wholes("seen_from", -DataReader.MOST, DataReader.MOST)
	if seen.size() % 3 != 0:
		values.fail("a player's sight is cut off")
		return
	for i: int in range(0, seen.size(), 3):
		var slot: int = seen[i]
		var from: Vector2i = Vector2i(seen[i + 1], seen[i + 2])
		if state.player(slot) == null or _seen_from.has(slot) or not state.region.has_tile(from):
			values.fail("the sight of slot %d isn't of one player in the region" % slot)
			return
		_seen_from[slot] = from
		visible[slot] = sight(state.region, from, radius_of(slot), state.next_door)
	revealed = values.tiles("revealed", state.region)
	revealed.sort()


## Works out again the sight of every player who moved; players who left lose theirs.
func _update(state: GameState) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		var player: Entity = state.player(slot)
		if player == null:
			var _lost: bool = visible.erase(slot)
			var _forgot: bool = _seen_from.erase(slot)
			var _narrowed: bool = _wider.erase(slot)
		elif not _seen_from.has(slot) or _seen_from[slot] != player.tile:
			_seen_from[slot] = player.tile
			visible[slot] = sight(state.region, player.tile, radius_of(slot), state.next_door)


## The tiles of `region`, or of the ground next door (#191), within `radius` of `from` that a
## straight line reaches without passing over rock, in Hex.disc's order: sight crosses the seam.
## Every line is worked out once per radius, from the origin, and
## walked from `from` (#289): a hex line doesn't depend on where it starts, so the tiles are the
## same as drawing each line afresh, without the work.
static func sight(
		region: Region,
		from: Vector2i,
		radius: int,
		next_door: Dictionary[Vector2i, String] = {},
) -> Array[Vector2i]:
	var seen: Array[Vector2i] = []
	var lines: Array = _lines_within(radius)
	var ends: Array[Vector2i] = Hex.disc(radius)
	for i: int in ends.size():
		var tile: Vector2i = from + ends[i]
		var between: Array[Vector2i] = lines[i]
		if not _ground(
			region,
			next_door,
			tile,
		).is_empty() and _clear(region, next_door, from, between):
			seen.append(tile)
	return seen


## Whether nothing between a line's ends blocks sight, the line's tiles between them given as
## offsets from `from`: no rock, and no gap in the region or next door.
static func _clear(
		region: Region,
		next_door: Dictionary[Vector2i, String],
		from: Vector2i,
		between: Array[Vector2i],
) -> bool:
	for offset: Vector2i in between:
		var ground: String = _ground(region, next_door, from + offset)
		if ground.is_empty() or ground == Region.BLOCKED:
			return false
	return true


## The terrain of `tile`, in the region or next door, or "" where there's no ground.
static func _ground(
		region: Region,
		next_door: Dictionary[Vector2i, String],
		tile: Vector2i,
) -> String:
	if region.has_tile(tile):
		return region.terrain[tile]
	return next_door.get(tile, "")


## The tiles between the origin and each tile of Hex.disc(radius), in the disc's order, worked out
## once per radius. Derived data, so it's in no hash.
static func _lines_within(radius: int) -> Array:
	if not _lines.has(radius):
		var lines: Array = []
		for end: Vector2i in Hex.disc(radius):
			var path: Array[Vector2i] = Hex.line(Vector2i.ZERO, end)
			var between: Array[Vector2i] = []
			between.assign(path.slice(1, maxi(path.size() - 1, 1)))
			lines.append(between)
		_lines[radius] = lines
	return _lines[radius]
