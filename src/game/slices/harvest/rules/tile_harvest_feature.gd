class_name TileHarvestFeature
extends Feature
## Harvesting a tile by hand (#696): a player standing on, or next to, a tile whose kind bare hands
## can harvest (TileKinds.harvested_by_hand) presses the interact action (Command.interact). After
## HARVEST_TICKS without walking off, the tile drops its materials and turns into its depleted kind
## (GameState.change_tile), which the instance keeps until it's purged (#212): then the tile comes
## back. Every player in the instance rolls their own (#74) on the kind's tile table, from this
## feature's own stream, in slot order. The tile harvested is the one the player stands on, else the
## first one beside them in Hex.DIRECTIONS' order. A player knocked down, or whose tile changes
## first (another player harvested it), stops. Gear (#697) and a species' skill (#698) harvest
## other kinds later. The ticks and the rolls are in Tuning.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "tile_harvest"
const HARVEST_TICKS: int = Tuning.TILE_HARVEST_TICKS
const ROLLS_PER_PLAYER: int = Tuning.TILE_HARVEST_ROLLS_PER_PLAYER
## No tile to harvest: never a region's, whose tiles are near the origin.
const NO_TILE: Vector2i = Vector2i(-DataReader.MOST, -DataReader.MOST)

## Each harvestable kind's tile table, by the kind's id; a kind without one drops nothing.
var tables: Dictionary[String, LootTable] = {}
## Each harvesting player's tile, by slot, where they stood when they began, and the ticks left.
var targets: Dictionary[int, Vector2i] = {}
var spots: Dictionary[int, Vector2i] = {}
var left: Dictionary[int, int] = {}
var _rng: Rng


func _init(kind_tables: Dictionary[String, LootTable] = {}) -> void:
	tables = kind_tables


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [MovementFeature.ID]
	return needed


## The knocked-down players, who harvest nothing.
func after() -> Array[String]:
	var earlier: Array[String] = [KnockdownFeature.ID]
	return earlier


func start(state: GameState) -> void:
	_rng = Rng.new(state.rng_seed, stream())


## Whether `region` holds a tile bare hands can harvest: an instance has this feature then
## (RegionFeatures).
static func has_harvestable(region: Region) -> bool:
	for tile: Vector2i in region.terrain:
		if TileKinds.harvested_by_hand(region.terrain[tile]):
			return true
	return false


## Every player goes on with their harvest, or begins one with the interact press, in slot order.
func step(state: GameState, commands: Array[Command]) -> void:
	var knockdown: KnockdownFeature = state.feature(KnockdownFeature.ID) as KnockdownFeature
	for slot: int in GameState.MAX_PLAYERS:
		var player: Entity = state.player(slot)
		if player == null or (knockdown != null and knockdown.is_down(player.id)):
			_stop(slot)
		elif targets.has(slot):
			_go_on(state, slot, player)
		else:
			var command: Command = Command.of(commands, slot)
			if command != null and command.interact:
				_begin(state, slot, player)


## Another player harvested the tile first, or a rule changed it: whoever harvests it stops.
func tile_changed(_state: GameState, tile: Vector2i) -> void:
	for slot: int in _slots():
		if targets[slot] == tile:
			_stop(slot)


## The tile the player `player` harvests when they press interact: the one they stand on, else the
## first beside them bare hands can harvest; NO_TILE for none.
static func target_of(state: GameState, player: Entity) -> Vector2i:
	var around: Array[Vector2i] = [player.tile]
	for direction: Vector2i in Hex.DIRECTIONS:
		around.append(player.tile + direction)
	for tile: Vector2i in around:
		if state.region.has_tile(tile) and TileKinds.harvested_by_hand(state.region.terrain[tile]):
			return tile
	return NO_TILE


func _begin(state: GameState, slot: int, player: Entity) -> void:
	var tile: Vector2i = target_of(state, player)
	if tile == NO_TILE:
		return
	targets[slot] = tile
	spots[slot] = player.tile
	left[slot] = HARVEST_TICKS


## One tick more of `slot`'s harvest: it stops when they walked off, and the tile drops its
## materials once its ticks are up.
func _go_on(state: GameState, slot: int, player: Entity) -> void:
	if player.tile != spots[slot]:
		_stop(slot)
		return
	left[slot] -= 1
	if left[slot] > 0:
		return
	var tile: Vector2i = targets[slot]
	var kind: String = state.region.terrain[tile]
	_stop(slot)
	var loot: Dictionary[int, Dictionary] = {}
	for each: int in GameState.MAX_PLAYERS:
		if state.player(each) != null:
			loot[each] = _roll(kind, HostSettings.drops(state, ROLLS_PER_PLAYER))
	var _changed: bool = state.change_tile(tile, TileKinds.harvested_into(kind))
	state.events.append(TileHarvested.new(player.id, tile, kind, loot))


## `times` rolls on `kind`'s tile table, added up as {item id: amount}; nothing without one.
func _roll(kind: String, times: int) -> Dictionary[String, int]:
	var none: Dictionary[String, int] = {}
	return tables[kind].roll_times(_rng, times, null) if tables.has(kind) else none


func _stop(slot: int) -> void:
	var _target: bool = targets.erase(slot)
	var _spot: bool = spots.erase(slot)
	var _left: bool = left.erase(slot)


func hash_values() -> Array[int]:
	var values: Array[int] = []
	for slot: int in _slots():
		values.append_array([slot, targets[slot].x, targets[slot].y, spots[slot].x, spots[slot].y])
		values.append(left[slot])
	values.append_array(_rng.hash_values())
	return values


## The harvests going on, by slot in order, and the stream's state; the tables follow from the
## content.
func save_values() -> Dictionary:
	var slots: Array[int] = _slots()
	var ticks: Array[int] = []
	var tiles: Array[Vector2i] = []
	var stood: Array[Vector2i] = []
	for slot: int in slots:
		ticks.append(left[slot])
		tiles.append(targets[slot])
		stood.append(spots[slot])
	return {
		"rng": _rng.hash_values(),
		"slots": slots,
		"targets": DataReader.flat(tiles),
		"spots": DataReader.flat(stood),
		"left": ticks,
	}


func load_values(state: GameState, values: DataReader) -> void:
	var restored: Rng = Rng.restored(values.wholes("rng", 0, Rng.MASK))
	var slots: Array[int] = values.wholes("slots", 0, GameState.MAX_PLAYERS - 1)
	var tiles: Array[Vector2i] = values.tiles("targets", state.region)
	var stood: Array[Vector2i] = values.tiles("spots", state.region)
	var ticks: Array[int] = values.wholes("left", 1, HARVEST_TICKS)
	if values.failed():
		return
	var sizes: bool = tiles.size() == slots.size() and stood.size() == slots.size()
	if restored == null or not sizes or ticks.size() != slots.size():
		values.fail("feature %s's harvests or stream don't hold together" % ID)
		return
	_rng = restored
	for i: int in slots.size():
		if targets.has(slots[i]):
			values.fail("feature %s holds two harvests of slot %d" % [ID, slots[i]])
			return
		targets[slots[i]] = tiles[i]
		spots[slots[i]] = stood[i]
		left[slots[i]] = ticks[i]


## The harvesting players' slots, in order.
func _slots() -> Array[int]:
	var slots: Array[int] = []
	slots.assign(targets.keys())
	slots.sort()
	return slots
