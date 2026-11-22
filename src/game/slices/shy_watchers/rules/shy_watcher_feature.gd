class_name ShyWatcherFeature
extends Feature
## Shy watchers (#2416, from #1995): a wild monster its region's legend marks `, shy` (WildSpot)
## stands out of reach, shown so the look plays its idle clip, and can't be struck, ringed or
## dominated. Held in place (WildMonsterFeature.hold), it never walks toward ringable ground,
## attacks, hunts, forages or sleeps.
##
## When any player comes within TRIGGER_RANGE tiles, it hides through HidingFeature (#202) without
## a jump-out and begins leaving: it steps away from the nearest player at its pace (WildPace) for
## up to LEAVE_STEPS steps (or until cornered) and is then removed from the region, raising
## ShyMonsterLeft. Once a shy watcher leaves its spot, that spot is recorded in the world store so
## it never comes back to that spot for that world, even after the instance is purged or reloaded.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "shy_watchers"
## How near any player comes before a shy watcher hides and starts leaving, in tiles.
const TRIGGER_RANGE: int = Tuning.SHY_TRIGGER_RANGE
## How many steps away out of sight a shy watcher takes before leaving the region.
const LEAVE_STEPS: int = Tuning.SHY_LEAVE_STEPS
## Key in a player's world store entry: list of [instance_name, q, r] spots that already left.
const LEFT_KEY: String = "left"

## The instance's blueprint id, paired with each spot in the world store.
var instance_name: String
## Each standing shy watcher's starting spot in the region, by entity id.
var spots: Dictionary[int, Vector2i] = {}
## Each shy watcher currently stepping away out of sight, as steps left (>= 1), by entity id.
var leaving: Dictionary[int, int] = {}
## Ticks remaining until the next step away for each leaving shy watcher (>= 1), by entity id.
var waits: Dictionary[int, int] = {}
## Spots in this region whose shy watcher has already left, sorted.
var gone: Array[Vector2i] = []


func _init(instance_id: String = "") -> void:
	instance_name = instance_id


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [WildMonsterFeature.ID, HidingFeature.ID]
	return needed


## Marks every wild monster on a `, shy` spot, keeping it shown, held in place and awake.
func start(state: GameState) -> void:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var hiding: HidingFeature = state.feature(HidingFeature.ID) as HidingFeature
	var placed: Dictionary[Vector2i, String] = state.region.placed(WildSpotPlacements.KIND)
	for monster: int in wild.monsters:
		var tile: Vector2i = state.entity(monster).tile
		var spot: WildSpot = WildSpot.read(placed[tile]) if placed.has(tile) else null
		if spot != null and spot.shy:
			spots[monster] = tile
			hiding.unhide(monster)
			wild.hold(monster, true)
			wild.sleep(monster, false)


## Clears any shy watcher whose spot already left in this world, keeps the rest awake, hides any
## watcher a player came within TRIGGER_RANGE of, and steps leaving watchers away at their pace.
func step(state: GameState, _commands: Array[Command]) -> void:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var hiding: HidingFeature = state.feature(HidingFeature.ID) as HidingFeature
	for monster: int in _watchers():
		if not wild.monsters.has(monster):
			_forget(monster)
			continue
		if gone.has(spots[monster]) or _left_in_world(state, spots[monster]):
			_record_gone(spots[monster])
			state.remove_entity(monster)
			continue
		wild.sleep(monster, false)
		if leaving.has(monster):
			_step_leaving(state, wild, monster)
		elif _player_within(state, state.entity(monster).tile, TRIGGER_RANGE):
			hiding.hide(monster, true)
			leaving[monster] = LEAVE_STEPS
			waits[monster] = _pace(state, wild, monster)


func entity_removed(_state: GameState, removed_id: int) -> void:
	_forget(removed_id)


## Whether the entity with this id is a shy watcher.
func is_shy(entity_id: int) -> bool:
	return spots.has(entity_id)


## Whether the shy watcher with this id has already hidden and is stepping away.
func is_leaving(entity_id: int) -> bool:
	return leaving.has(entity_id)


## Whether any wild monster spot of `region` is marked shy, so its instance needs the feature.
static func has_shy(region: Region) -> bool:
	var placed: Dictionary[Vector2i, String] = region.placed(WildSpotPlacements.KIND)
	for tile: Vector2i in placed:
		var spot: WildSpot = WildSpot.read(placed[tile])
		if spot != null and spot.shy:
			return true
	return false


func hash_values() -> Array[int]:
	var values: Array[int] = [spots.size()]
	for monster: int in _watchers():
		var spot: Vector2i = spots[monster]
		values.append_array([monster, spot.x, spot.y])
	values.append(leaving.size())
	values.append_array(DataReader.flat_pairs(leaving))
	values.append(waits.size())
	values.append_array(DataReader.flat_pairs(waits))
	values.append(gone.size())
	values.append_array(DataReader.flat(gone))
	return values


func save_values() -> Dictionary:
	var saved_spots: Array[int] = []
	for monster: int in _watchers():
		var spot: Vector2i = spots[monster]
		saved_spots.append_array([monster, spot.x, spot.y])
	return {
		"spots": saved_spots,
		"leaving": DataReader.flat_pairs(leaving),
		"waits": DataReader.flat_pairs(waits),
		"gone": DataReader.flat(gone),
	}


func load_values(state: GameState, values: DataReader) -> void:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	spots.clear()
	leaving.clear()
	waits.clear()
	gone.clear()
	_load_spots(state, wild, values)
	_load_leaving(values)
	_load_gone(state, values)
	if values.failed():
		return
	for monster: int in _watchers():
		wild.hold(monster, true)


## Restores each standing shy watcher's original spot, validating it against the region's legend.
func _load_spots(state: GameState, wild: WildMonsterFeature, values: DataReader) -> void:
	var flat: Array[int] = values.wholes("spots", -DataReader.MOST, DataReader.MOST)
	if flat.size() % 3 != 0:
		values.fail("shy watcher spots aren't entity and tile triples")
		return
	for i: int in range(0, flat.size(), 3):
		var monster: int = flat[i]
		var tile: Vector2i = Vector2i(flat[i + 1], flat[i + 2])
		if (
			monster < 1
			or not wild.monsters.has(monster)
			or spots.has(monster)
			or not _is_shy_spot(state.region, tile)
		):
			values.fail("shy watcher %d isn't one wild monster on a shy spot" % monster)
			return
		spots[monster] = tile


## Restores the leaving countdowns and step waits, requiring their keys to match.
func _load_leaving(values: DataReader) -> void:
	var saved_leaving: Dictionary[int, int] = values.pairs("leaving", 0, DataReader.MOST)
	var saved_waits: Dictionary[int, int] = values.pairs("waits", 0, DataReader.MOST)
	if saved_leaving.size() != saved_waits.size():
		values.fail("shy watcher leaving and waits don't match")
		return
	for monster: int in saved_leaving:
		var steps_left: int = saved_leaving[monster]
		var wait_left: int = saved_waits.get(monster, 0)
		if (
			not spots.has(monster)
			or steps_left < 1
			or steps_left > LEAVE_STEPS
			or wait_left < 1
		):
			values.fail("shy watcher %d has invalid leaving state" % monster)
			return
		leaving[monster] = steps_left
		waits[monster] = wait_left


## Restores the spots that already left in this region.
func _load_gone(state: GameState, values: DataReader) -> void:
	var saved_gone: Array[Vector2i] = values.tiles("gone", state.region)
	for tile: Vector2i in saved_gone:
		if not _is_shy_spot(state.region, tile) or gone.has(tile):
			values.fail("gone shy spot %s isn't one shy spot of the region" % tile)
			return
		gone.append(tile)
	gone.sort()


## Steps the leaving shy watcher `monster` away from the nearest player once its pace wait expires,
## removing it from the region and raising ShyMonsterLeft once it finishes or is cornered.
func _step_leaving(state: GameState, wild: WildMonsterFeature, monster: int) -> void:
	waits[monster] -= 1
	if waits[monster] > 0:
		return
	var entity: Entity = state.entity(monster)
	var next: Vector2i = _step_away(state, entity.tile)
	if next != entity.tile:
		entity.tile = next
		leaving[monster] -= 1
		if leaving[monster] > 0:
			waits[monster] = _pace(state, wild, monster)
			return
	_finish_leaving(state, wild, monster)


## Removes `monster` from the region, records its spot as permanently gone for this world, and
## raises ShyMonsterLeft.
func _finish_leaving(state: GameState, wild: WildMonsterFeature, monster: int) -> void:
	var spot: Vector2i = spots[monster]
	var tile: Vector2i = state.entity(monster).tile
	var species: String = wild.species_of(monster)
	var short_id: String = wild.short_id_of(monster)
	_record_gone(spot)
	_remember_in_world(state, spot)
	state.remove_entity(monster)
	state.events.append(ShyMonsterLeft.new(monster, spot, tile, species, short_id))


## Records `spot` in the first present player's world store so a purged or reloaded instance in the
## same world never respawns this shy watcher.
func _remember_in_world(state: GameState, spot: Vector2i) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		if state.player(slot) == null:
			continue
		var entry: Dictionary = state.store(slot, ID)
		var listed: Variant = entry.get(LEFT_KEY)
		var all: Array = listed if listed is Array else []
		var marker: Array = [instance_name, spot.x, spot.y]
		if not all.has(marker):
			all.append(marker)
		entry[LEFT_KEY] = all
		return


## Whether any player's world store records that `spot` in this instance already left.
func _left_in_world(state: GameState, spot: Vector2i) -> bool:
	for slot: int in GameState.MAX_PLAYERS:
		var listed: Variant = state.stored(slot, ID).get(LEFT_KEY, [])
		if not listed is Array:
			continue
		var entries: Array = listed
		for item: Variant in entries:
			if not item is Array:
				continue
			var parts: Array = item
			if (parts.size() == 3
					and parts[0] == instance_name
					and parts[1] is int
					and parts[2] is int):
				var q: int = parts[1]
				var r: int = parts[2]
				if q == spot.x and r == spot.y:
					return true
	return false


func _record_gone(spot: Vector2i) -> void:
	if not gone.has(spot):
		gone.append(spot)
		gone.sort()


func _forget(entity_id: int) -> void:
	var _dropped: bool = spots.erase(entity_id)
	_dropped = leaving.erase(entity_id)
	_dropped = waits.erase(entity_id)


func _watchers() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(spots.keys())
	ids.sort()
	return ids


## The open walkable neighbour of `from` that moves furthest from the nearest player, or `from`
## when cornered. Ignores ringability since shy watchers stand out of reach behind trees.
static func _step_away(state: GameState, from: Vector2i) -> Vector2i:
	var threat: Entity = _nearest_player(state, from)
	var best: Vector2i = from
	var best_dist: int = Hex.distance(from, threat.tile) if threat != null else -1
	for direction: Vector2i in Hex.DIRECTIONS:
		var candidate: Vector2i = from + direction
		if not state.region.is_walkable(candidate) or _occupied(state, candidate):
			continue
		if threat == null:
			return candidate
		var dist: int = Hex.distance(candidate, threat.tile)
		if dist > best_dist:
			best_dist = dist
			best = candidate
	return best


static func _nearest_player(state: GameState, from: Vector2i) -> Entity:
	var best: Entity = null
	var best_dist: int = DataReader.MOST
	for slot: int in GameState.MAX_PLAYERS:
		var player: Entity = state.player(slot)
		if player == null:
			continue
		var dist: int = Hex.distance(from, player.tile)
		if dist < best_dist:
			best_dist = dist
			best = player
	return best


static func _occupied(state: GameState, tile: Vector2i) -> bool:
	for entity: Entity in state.entities:
		if entity.tile == tile:
			return true
	return false


static func _player_within(state: GameState, tile: Vector2i, radius: int) -> bool:
	for slot: int in GameState.MAX_PLAYERS:
		var player: Entity = state.player(slot)
		if player != null and Hex.distance(player.tile, tile) <= radius:
			return true
	return false


static func _pace(state: GameState, wild: WildMonsterFeature, monster: int) -> int:
	return WildPace.paced(state, WildMonsterFeature.STEP_TICKS, wild.rage_of(monster))


static func _is_shy_spot(region: Region, tile: Vector2i) -> bool:
	var placed: Dictionary[Vector2i, String] = region.placed(WildSpotPlacements.KIND)
	var spot: WildSpot = WildSpot.read(placed[tile]) if placed.has(tile) else null
	return spot != null and spot.shy
